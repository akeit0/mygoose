"""Build the pinned Goose compiler in .toolchain/goose (Git, CMake 3.27+, C++20).

python3 tools/bootstrap.py
python tools/bootstrap.py --generator Ninja
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(*args: str, cwd: Path = ROOT) -> None:
    print("+ " + " ".join(str(arg) for arg in args), flush=True)
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def git_output(source: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--generator", help="CMake generator; defaults to the host's usual generator")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if args.jobs < 1: parser.error("--jobs must be positive")
    for tool in ("git", "cmake"):
        if not shutil.which(tool): parser.error(f"Install {tool} and add it to PATH first")
    pin = json.loads((ROOT / "tools/toolchain.json").read_text(encoding="utf-8"))
    source = ROOT / ".toolchain/goose"
    if not source.exists():
        source.mkdir(parents=True)
        run("git", "init", str(source))
        run("git", "remote", "add", "origin", pin["repository"], cwd=source)
    if not (source / ".git").is_dir():
        parser.error(f"{source} already exists but is not a compiler checkout")
    if git_output(source, "remote", "get-url", "origin") != pin["repository"]:
        parser.error(f"{source} has a different origin; keep it and choose another checkout for MyGoose")
    if git_output(source, "status", "--porcelain", "--untracked-files=no"):
        parser.error(f"{source} has compiler changes; commit or move them before bootstrapping")
    head = subprocess.run(["git", "-C", str(source), "rev-parse", "--verify", "HEAD"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    if head.returncode or head.stdout.strip() != pin["revision"]:
        run("git", "fetch", "--depth", "1", "origin", pin["revision"], cwd=source)
        run("git", "checkout", "--detach", pin["revision"], cwd=source)
    build = source / "build"
    configure = ["cmake", "-S", source, "-B", build, "-DCMAKE_BUILD_TYPE=Release"]
    if args.generator: configure += ["-G", args.generator]
    run(*configure)
    run("cmake", "--build", build, "--config", "Release", "--parallel", str(args.jobs))
    print("Goose is ready. Run python3 tools/build.py gallery --run", flush=True)


if __name__ == "__main__":
    main()
