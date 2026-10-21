"""Emit C on Windows, then compile/test real Linux binaries in WSL2.

python tools/wsl.py all --mode small
python tools/wsl.py test --mode debug
python tools/wsl.py gallery --run
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", choices=("all", "test", "rich-test", "images-test", "charts-test", "performance-test", "performance-bench", "monitor", "monitor-test", "bench", "counter", "gallery", "list", "quotes", "events", "editor", "motion", "rich", "images", "charts", "table", "performance"), nargs="?", default="test")
    parser.add_argument("--mode", choices=("debug", "small", "fast"), default="debug")
    parser.add_argument("--distro", default="Ubuntu")
    parser.add_argument("--goose")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if os.name != "nt": parser.error("Run this helper from Windows; on Linux use tools/build.py directly")
    emit = [sys.executable, str(ROOT/"tools/build.py"), args.target, "--mode", args.mode, "--emit-only"]
    if args.goose: emit += ["--goose", args.goose]
    subprocess.run(emit, cwd=ROOT, check=True)
    wsl = ["wsl.exe", "-d", args.distro, "--exec"]
    path = subprocess.check_output([*wsl, "wslpath", "-u", ROOT.as_posix()], encoding="utf-8").strip()
    command = ["wsl.exe", "-d", args.distro, "--cd", path, "--exec"]
    # Private display keeps clipboard protocol tests away from WSLg/Windows.
    if args.target in ("test", "rich-test", "images-test", "charts-test", "performance-test", "performance-bench", "monitor-test", "all"):
        # Keep the private server alive between the native lifecycle test's
        # close/reopen operations; Xvfb's reset can race a new XOpenDisplay.
        command += ["env", "MYGOOSE_TEST_CLIPBOARD=1", "xvfb-run", "-a", "-s", "-screen 0 1280x1024x24 -noreset"]
    command += ["python3", "tools/build.py", args.target, "--mode", args.mode, "--from-c", f"build/portable-{args.mode}"]
    if args.run: command.append("--run")
    subprocess.run(command, cwd=ROOT, check=True)

if __name__ == "__main__": main()
