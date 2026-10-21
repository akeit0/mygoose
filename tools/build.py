"""Build MyGoose with Goose and a native C compiler; no Python packages needed.

python tools/build.py all --mode small
python tools/build.py gallery --run
python tools/build.py test --mode debug
python tools/build.py bench --run
"""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import platform
import shlex
import re
import time

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ("counter", "gallery", "list", "quotes", "events", "editor", "motion", "rich", "canvas", "images", "charts", "table", "performance")

def execute(argv: list[str], *, env=None) -> str:
    p = subprocess.run([str(x) for x in argv], cwd=ROOT, env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
    if p.returncode:
        print(p.stdout, end="", file=sys.stderr)
        raise SystemExit(p.returncode)
    return p.stdout

def compiler(explicit: str | None, env_name: str, name: str, managed: tuple[Path, ...] = ()) -> str:
    candidate = explicit or os.environ.get(env_name)
    if not candidate:
        candidate = next((str(p) for p in managed if p.is_file()), None) or shutil.which(name)
    if candidate is None:
        option = "--goose" if env_name == "GOOSE" else "--cc"
        setup = " Run python tools/bootstrap.py first, or" if env_name == "GOOSE" else ""
        raise SystemExit(f"Cannot find {name}.{setup} pass {option} or set {env_name}; compilers on PATH are also supported.")
    resolved = shutil.which(candidate) or (str(Path(candidate).resolve()) if Path(candidate).is_file() else None)
    if not resolved:
        raise SystemExit(f"Compiler does not exist: {candidate}")
    return resolved

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", choices=(*EXAMPLES, "monitor", "monitor-test", "monitor-bench", "performance-test", "performance-bench", "test", "rich-test", "images-test", "charts-test", "bench", "all"), nargs="?", default="all")
    parser.add_argument("--mode", choices=("small", "fast", "debug"), default="small")
    parser.add_argument("--goose")
    parser.add_argument("--cc", "--gcc", dest="cc", help="Native C compiler (Apple Clang on macOS, GCC on Windows/Linux)")
    parser.add_argument("--emit-only", action="store_true", help="Emit portable C into build/portable-MODE without compiling")
    parser.add_argument("--from-c", type=Path, help="Compile C emitted by --emit-only; no local Goose compiler needed")
    parser.add_argument("--run", action="store_true")
    subsystem = parser.add_mutually_exclusive_group()
    subsystem.add_argument("--gui", dest="subsystem", action="store_const", const="gui", help="Windows GUI subsystem: no console window (default for UI apps)")
    subsystem.add_argument("--console", dest="subsystem", action="store_const", const="console", help="Windows console subsystem for diagnostics (default for tests/benchmarks)")
    parser.add_argument("--dump", type=Path, help="Write the first frame to a PPM file and exit")
    args = parser.parse_args()
    host = {"Windows": "windows", "Linux": "linux", "Darwin": "macos"}.get(platform.system())
    if host is None: parser.error("Supported platforms: Windows, Linux, macOS")
    if args.emit_only and (args.from_c or args.run or args.dump): parser.error("--emit-only cannot run or consume C")
    if args.subsystem and host != "windows": parser.error("--gui/--console require Windows")
    if args.target == "all" and (args.run or args.dump):
        parser.error("Choose one target for --run or --dump")
    goose_build = ROOT/".toolchain/goose/build"
    goose = None if args.from_c else compiler(args.goose, "GOOSE", "goose", (
        goose_build/"Release/goose.exe", goose_build/"goose.exe", goose_build/"goose"))
    gcc = None if args.emit_only else compiler(args.cc, "MYGOOSE_CC", "clang" if host == "macos" else "gcc")
    outdir = ROOT/"build"/(("portable-" if args.emit_only else "" if host == "windows" else host+"-") + args.mode)
    outdir.mkdir(parents=True, exist_ok=True)
    # MinGW + LTO + -fdata-sections puts zero-filled scratch arrays into the
    # on-disk .data section. Leave data sections together so those stay in BSS.
    flags = ["-std=c11", "-ffunction-sections", "-fno-ident", "-DGS_STACK_RESERVE=16777216"]
    flags += {"small": ["-Os", "-flto"], "fast": ["-O3", "-flto"], "debug": ["-O0", "-g", "-DGS_DEBUG=1"]}[args.mode]
    native = ROOT/"native"/host/("platform.m" if host == "macos" else "platform.c")
    native_flags = []
    if not args.emit_only and host == "linux":
        if not shutil.which("pkg-config"): raise SystemExit("Install pkg-config, libx11-dev, libcairo2-dev, libpango1.0-dev")
        native_flags = shlex.split(execute(["pkg-config", "--cflags", "x11", "pangocairo"]))
        libraries = shlex.split(execute(["pkg-config", "--libs", "x11", "pangocairo"])) + ["-lm", "-pthread"]
    elif host == "macos":
        libraries = ["-framework", "Cocoa", "-framework", "CoreText", "-framework", "CoreGraphics", "-framework", "QuartzCore"]
    else: libraries = ["-luser32", "-lgdi32", "-limm32", "-ld2d1", "-ldwrite"]
    warnings = ["-Wall", "-Wextra", "-Werror", "-Wno-cast-function-type"]
    obj = outdir/"platform.o"
    native_files = [*sorted((ROOT/"native").glob("*.h")), *sorted(native.parent.rglob("*"))]
    native_sources = b"".join(p.read_bytes() for p in native_files if p.suffix in (".h", ".c", ".m"))
    signature = hashlib.sha256(native_sources + repr((gcc, flags, native_flags, host)).encode()).hexdigest()
    sigfile = outdir/"platform.sha256"
    if not args.emit_only and (not obj.exists() or not sigfile.exists() or sigfile.read_text() != signature):
        execute([gcc, *flags, *native_flags, *warnings, "-c", native, "-o", obj])
        sigfile.write_text(signature)
    apps = ("monitor", "monitor-test", "monitor-bench")
    targets = (*EXAMPLES, *apps, "performance-test", "performance-bench", "test", "rich-test", "images-test", "charts-test", "bench") if args.target == "all" else (args.target,)
    renderer = "d2d" if host == "windows" else "cairo" if host == "linux" else "coregraphics"
    for name in targets:
        source = ROOT/({"monitor": "apps/monitor/main.goose", "monitor-test": "apps/monitor/test.goose", "monitor-bench": "apps/monitor/bench.goose", "performance-test": "tests/performance.goose", "performance-bench": "apps/performance/bench.goose", "test": "tests/ui.goose", "rich-test": "tests/rich.goose", "images-test": "tests/images.goose", "charts-test": "tests/charts.goose", "bench": "bench/frames.goose"}.get(name, f"examples/{name}.goose"))
        cfile = outdir/f"{name}.c"
        exe = outdir/(name + (".exe" if host == "windows" else ""))
        t = time.perf_counter()
        emit = [goose, "-O2", "--standalone", "-o", cfile, source]
        if args.mode == "debug": emit.insert(1, "-DGS_DEBUG=1")
        if args.from_c:
            emitted = args.from_c.resolve()/f"{name}.c"
            if not emitted.is_file(): raise SystemExit(f"Missing portable C: {emitted}")
            shutil.copyfile(emitted, cfile)
        else: execute(emit)
        if args.emit_only:
            print(f"Emitted {cfile.relative_to(ROOT)}", flush=True)
            continue
        optional_objects = []
        extra_libraries = []
        if name in apps:
            sampler = ROOT/"apps/monitor/native"/f"{host}.c"
            if not sampler.is_file(): raise SystemExit(f"Monitor sampling is not implemented for {host} yet")
            sampler_obj = outdir/"monitor-sample.o"
            execute([gcc, *flags, *warnings, "-c", sampler, "-o", sampler_obj])
            optional_objects.append(sampler_obj)
            icon_source = sampler.parent/("icons_windows.c" if host == "windows" else "icons_macos.m" if host == "macos" else "icons_other.c")
            icon_obj = outdir/"monitor-icons.o"
            execute([gcc, *flags, *warnings, "-c", icon_source, "-o", icon_obj])
            optional_objects.append(icon_obj)
            if host == "windows": extra_libraries = ["-lpsapi", "-liphlpapi", "-lpdh", "-ladvapi32", "-lshell32", "-lole32"]
            elif host == "macos": extra_libraries = ["-framework", "IOKit", "-framework", "CoreFoundation"]
        # Optional packages own separate native objects. MinGW can retain DLL
        # import entries from unused functions in a linked object, so putting
        # vector code inside platform.o would still tax basic applications.
        uses_charts = bool(re.search(r"\bmg_chart\s*\(", cfile.read_text(encoding="utf-8")))
        if uses_charts:
            chart_obj = outdir/"charts.o"
            chart_source = ROOT/"extras/charts/native"/("macos.c" if host == "macos" else "charts.c")
            execute([gcc, *flags, *warnings, "-c", chart_source, "-o", chart_obj])
            optional_objects.append(chart_obj)
        if re.search(r"\bmg_vector\s*\(", cfile.read_text(encoding="utf-8")):
            vector_dir = ROOT/"extras/graphics/native"
            vector_source = vector_dir/f"{host}.c"
            vector_obj = outdir/"vector.o"
            vector_key = hashlib.sha256(vector_source.read_bytes() + (vector_dir/"vector.h").read_bytes() +
                (ROOT/"native/vector_target.h").read_bytes() + (ROOT/"native/backend.h").read_bytes() +
                repr((gcc, flags, native_flags)).encode()).hexdigest()
            vector_sig = outdir/"vector.sha256"
            if not vector_obj.exists() or not vector_sig.exists() or vector_sig.read_text() != vector_key:
                execute([gcc, *flags, *native_flags, *warnings, "-c", vector_source, "-o", vector_obj])
                vector_sig.write_text(vector_key)
            optional_objects.append(vector_obj)
        if re.search(r"\bmg_image_(?:draw|create|paint)\s*\(", cfile.read_text(encoding="utf-8")):
            image_source = ROOT/"extras/images/native"/f"{host}.c"
            image_obj = outdir/"image.o"
            execute([gcc, *flags, *native_flags, *warnings, "-c", image_source, "-o", image_obj])
            optional_objects.append(image_obj)
        if re.search(r"\bmg_window_frame\s*\(", cfile.read_text(encoding="utf-8")):
            frame_source = ROOT/"extras/window/native"/("windows.c" if host == "windows" else "macos.m" if host == "macos" else "other.c")
            frame_obj = outdir/"window.o"
            execute([gcc, *flags, *warnings, "-c", frame_source, "-o", frame_obj])
            optional_objects.append(frame_obj)
            if host == "windows": extra_libraries.append("-ldwmapi")
        link = (["-Wl,--gc-sections", "-Wl,--stack,8388608", "-static-libgcc"] if host == "windows" else
                ["-Wl,-dead_strip", "-Wl,-stack_size,0x800000"] if host == "macos" else ["-Wl,--gc-sections"])
        if args.mode != "debug" and host != "macos": link.append("-s")
        if host == "windows":
            console = args.subsystem == "console" or (args.subsystem is None and (name.endswith("-test") or name in ("test", "bench", "monitor-bench", "performance-bench")))
            link.append("-mconsole" if console else "-mwindows")
        execute([gcc, *flags, cfile, obj, *optional_objects, "-o", exe, *link, *libraries, *extra_libraries])
        print(f"{name}: {exe.stat().st_size:,} bytes, {time.perf_counter()-t:.2f}s ({args.mode}, {host})", flush=True)
        if args.run or name in ("test", "rich-test", "images-test", "charts-test", "monitor-test", "performance-test") or args.dump:
            env = os.environ.copy()
            if args.dump:
                args.dump.resolve().parent.mkdir(parents=True, exist_ok=True)
                env["MYGOOSE_DUMP"] = str(args.dump.resolve())
            if name in ("test", "rich-test", "images-test", "charts-test", "monitor-test", "performance-test"):
                print(f"Renderer: {renderer}")
                print(execute([exe], env=env), end="")
            elif name in ("bench", "monitor-bench", "performance-bench") or args.dump:
                print(execute([exe], env=env), end="")
            else:
                subprocess.run([str(exe)], cwd=ROOT, env=env, check=True)
        if name == "monitor-test":
            native_test = outdir/("monitor-native-test" + (".exe" if host == "windows" else ""))
            execute([gcc, *flags, *warnings, ROOT/"apps/monitor/tests.c", "-o", native_test, *link, *extra_libraries, *(["-lm"] if host == "linux" else [])])
            print(execute([native_test]), end="", flush=True)
            if host == "windows":
                frame_test = outdir/"window-native-test.exe"
                execute([gcc, *flags, *native_flags, *warnings, ROOT/"tests/window_windows.c", "-o", frame_test, *link, *libraries, "-ldwmapi"])
                print(execute([frame_test]), end="", flush=True)
            elif host == "macos":
                frame_test = outdir/"window-native-test"
                execute([gcc, *flags, *warnings, ROOT/"tests/window_macos.m", "-o", frame_test, *link, *libraries])
                print(execute([frame_test]), end="", flush=True)
                icon_test = outdir/"icons-native-test"
                execute([gcc, *flags, *warnings, ROOT/"tests/icons_macos.m", "-o", icon_test, *link, *libraries])
                print(execute([icon_test]), end="", flush=True)
        if name in ("test", "rich-test", "images-test", "charts-test"):
            for test in (["vector"] if name == "rich-test" else ["images"] if name == "images-test" else ["charts"] if name == "charts-test" else ["native", host, *(["macos_context"] if host == "macos" else [])]):
                test_source = ROOT/"tests"/f"{test}.c"
                if host == "macos" and test == host: test_source = test_source.with_suffix(".m")
                if not test_source.is_file(): continue
                if test == "linux" and not os.environ.get("DISPLAY"):
                    print("SKIP: X11 window tests need DISPLAY (use xvfb-run -a)")
                    continue
                platform_test = outdir/(f"{test}-test" + (".exe" if host == "windows" else ""))
                objects = [obj, *optional_objects] if test in ("vector", "images", "charts") else [obj] if test == "native" else []
                execute([gcc, *flags, *native_flags, *warnings, test_source, *objects,
                         "-o", platform_test, *link, *libraries, *extra_libraries])
                print(execute([platform_test]), end="", flush=True)

if __name__ == "__main__":
    main()
