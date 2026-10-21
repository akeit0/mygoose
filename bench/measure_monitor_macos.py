"""Measure an already-built Monitor benchmark; no builds run during timing.

python3 bench/measure_monitor_macos.py --app build/macos-small/monitor-bench \
  --native build/monitor-native-bench --output build/monitor-results.json
Close other MyGoose apps first. Window runs use six seconds of warmup and
twelve seconds of measurement. The native probe supplies its own warmup.
"""
from __future__ import annotations
import argparse
import ctypes
import json
from pathlib import Path
import platform
import subprocess
import time


class Usage(ctypes.Structure):
    # Public rusage_info_v2 prefix. Memory is bytes; CPU tick fields are unused.
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [(name, ctypes.c_uint64) for name in (
        "user", "system", "idle_wakeups", "interrupt_wakeups", "pageins",
        "wired", "resident", "footprint", "start", "exit")]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--native", type=Path, help="Required only when measuring the native workload")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--workloads", nargs="+", choices=("native", "overview", "processes", "scroll"),
                        default=("native", "overview", "processes", "scroll"))
    parser.add_argument("--trace", action="store_true", help="Report sampler/build/paint/event-pump CPU phases")
    parser.add_argument("--settled", action="store_true", help="Warm steady windows for 65 seconds, then measure 30 seconds")
    args = parser.parse_args()
    if platform.system() != "Darwin": parser.error("This probe requires macOS")
    if "native" in args.workloads and args.native is None: parser.error("--native is required for the native workload")
    if args.runs < 1: parser.error("--runs must be positive")
    lib = ctypes.CDLL("/usr/lib/libproc.dylib")
    lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    results = []
    for workload, options in (("native", None), ("overview", ["--window", "--steady", "--overview"]),
                              ("processes", ["--window", "--steady"]), ("scroll", ["--window"])):
        if workload not in args.workloads: continue
        for run in range(args.runs):
            command = [str(args.native.resolve())] if options is None else [str(args.app.resolve()), *options]
            if workload in ("overview", "processes"):
                if args.trace: command.append("--trace")
                if args.settled: command.append("--settled")
            with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
                start = time.monotonic(); memory = []
                while process.poll() is None:
                    age = time.monotonic() - start
                    if workload in ("overview", "processes") and age >= (65 if args.settled else 6):
                        # Allocate the full ABI record although only its stable prefix is read.
                        buffer = ctypes.create_string_buffer(1024)
                        if lib.proc_pid_rusage(process.pid, 2, buffer) == 0:
                            usage = Usage.from_buffer_copy(buffer)
                            memory.append({"age": age, "rss": usage.resident, "footprint": usage.footprint})
                    time.sleep(.2)
                output = process.communicate()[0]
                if process.returncode: raise RuntimeError(f"{command}: {output}")
            results.append({"workload": workload, "run": run + 1, "output": output, "memory": memory})
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(results, indent=2) + "\n")
            print(workload, run + 1, output.strip(), flush=True)


if __name__ == "__main__":
    main()
