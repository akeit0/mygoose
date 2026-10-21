"""Build Finder-launchable Mac apps. Example: python3 tools/macos.py --install

Defaults to Gallery and Activity Monitor. Use --all for every UI example.
Bundles are self-contained and can be copied to another compatible Mac.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import os
import tempfile
import struct
from build import EXAMPLES, ROOT


def atomic_copy(source: str, destination: str) -> str:
    """Keep a running app's mapped executable intact while installing an update."""
    handle, temporary = tempfile.mkstemp(dir=Path(destination).parent, prefix=".mygoose-")
    os.close(handle)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return destination


def optimize_icon(path: Path, png_optimizer: str | None) -> None:
    """Compress embedded PNGs after iconutil, which re-encodes its inputs."""
    if not png_optimizer: return
    data = path.read_bytes()
    if data[:4] != b"icns" or struct.unpack_from(">I", data, 4)[0] != len(data):
        raise ValueError(f"Invalid generated icon: {path}")
    chunks = []; offset = 8
    while offset < len(data):
        kind, length = struct.unpack_from(">4sI", data, offset)
        if length < 8 or offset + length > len(data): raise ValueError("Invalid icon chunk")
        chunks.append((kind, data[offset + 8:offset + length])); offset += length
    # A table of contents would need its own offsets updated; iconutil's
    # current output has none. Preserve unfamiliar containers as generated.
    if any(kind == b"TOC " for kind, _ in chunks): return
    cache = {}; output = bytearray()
    with tempfile.TemporaryDirectory(prefix="mygoose-icon-") as temporary:
        source = Path(temporary) / "source.png"; result = Path(temporary) / "result.png"
        for kind, payload in chunks:
            if payload.startswith(b"\x89PNG\r\n\x1a\n"):
                if payload not in cache:
                    source.write_bytes(payload); result.unlink(missing_ok=True)
                    subprocess.run([png_optimizer, "-q", "-reduce", str(source), str(result)], check=True)
                    cache[payload] = min((payload, result.read_bytes()), key=len)
                payload = cache[payload]
            output.extend(struct.pack(">4sI", kind, len(payload) + 8) + payload)
    path.write_bytes(b"icns" + struct.pack(">I", len(output) + 8) + output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("targets", nargs="*", metavar="TARGET", help="UI example name or monitor; defaults to gallery and monitor")
    parser.add_argument("--all", action="store_true", help="Bundle all UI examples and the monitor")
    parser.add_argument("--mode", choices=("small", "fast", "debug"), default="small")
    parser.add_argument("--install", action="store_true", help="Copy apps into ~/Applications/MyGoose")
    parser.add_argument("--skip-build", action="store_true", help="Bundle binaries already built in this mode")
    parser.add_argument("--window-style", choices=("integrated", "standard"), default="integrated", help="Integrated content with native Mac buttons, or a standard title bar")
    args = parser.parse_args()
    for target in args.targets:
        if target not in (*EXAMPLES, "monitor"): parser.error(f"Unknown UI target: {target}")
    if platform.system() != "Darwin": parser.error("App bundles require macOS")
    if args.all and args.targets: parser.error("Choose --all or individual targets")
    targets = (*EXAMPLES, "monitor") if args.all else args.targets or ("gallery", "monitor")
    outdir = ROOT / "build" / f"macos-{args.mode}"
    icon_tool = ROOT / "build/macos-tools/icon"
    icon_source = ROOT / "tools/macos_icon.swift"
    if not icon_tool.exists() or icon_tool.stat().st_mtime < icon_source.stat().st_mtime:
        icon_tool.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", str(icon_source), "-o", str(icon_tool)], check=True)
    symbols = {"monitor": "gauge.with.dots.needle.67percent", "gallery": "square.grid.2x2.fill",
               "editor": "doc.text.fill", "charts": "chart.bar.fill", "images": "photo.fill", "canvas": "paintpalette.fill",
               "table": "tablecells.fill", "list": "list.bullet", "counter": "plus.circle.fill",
               "quotes": "quote.bubble.fill", "events": "bolt.fill", "motion": "wind", "rich": "sparkles", "performance": "waveform.path.ecg"}
    pngcrush = subprocess.run(["xcrun", "--find", "pngcrush"], capture_output=True, text=True)
    png_optimizer = pngcrush.stdout.strip() if pngcrush.returncode == 0 else None
    for target in targets:
        if not args.skip_build:
            subprocess.run([sys.executable, str(ROOT / "tools/build.py"), target, "--mode", args.mode], check=True)
        binary = outdir / target
        if not binary.is_file(): parser.error(f"Missing binary: {binary}; run without --skip-build")
        title = "MyGoose " + ("Activity Monitor" if target == "monitor" else target.title())
        bundle = outdir / "apps" / f"{title}.app"
        contents = bundle / "Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, contents / "MacOS" / target)
        resources = contents / "Resources"
        resources.mkdir(exist_ok=True)
        shutil.copy2(ROOT / "LICENSE", resources / "LICENSE")
        iconset = outdir / "icons" / f"{target}.iconset"
        subprocess.run([str(icon_tool), str(iconset), symbols[target]], check=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")], check=True)
        optimize_icon(resources / "AppIcon.icns", png_optimizer)
        info = {
            "CFBundleExecutable": target, "CFBundleName": title,
            "CFBundleDisplayName": title, "CFBundleIdentifier": f"dev.mygoose.{target}",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "2",
            "CFBundleShortVersionString": "0.2", "NSHighResolutionCapable": True,
            "NSPrincipalClass": "NSApplication",
            "CFBundleIconFile": "AppIcon.icns",
            "LSEnvironment": {"MYGOOSE_WINDOW_STYLE": args.window_style},
        }
        with (contents / "Info.plist").open("wb") as file: plistlib.dump(info, file)
        (contents / "PkgInfo").write_bytes(b"APPL????")
        subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
        if args.install:
            destination = Path.home() / "Applications/MyGoose" / bundle.name
            # Only replace one of our own previously installed bundles.
            if destination.exists():
                with (destination / "Contents/Info.plist").open("rb") as file: old = plistlib.load(file)
                if old.get("CFBundleIdentifier") != info["CFBundleIdentifier"]:
                    parser.error(f"Refusing to replace a different application: {destination}")
            shutil.copytree(bundle, destination, dirs_exist_ok=True, copy_function=atomic_copy)
            register = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
            if register.is_file(): subprocess.run([str(register), "-f", str(destination)], check=True)
            print(destination)
        else: print(bundle)


if __name__ == "__main__":
    main()
