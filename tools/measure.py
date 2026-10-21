"""Record reproducible frame timings, executable sizes, and native-window memory.
Build first: python tools/build.py all --mode small
Then: python tools/measure.py --mode small
"""
from __future__ import annotations
import argparse
import ctypes as C
from ctypes import wintypes as W
import datetime
import json
import os
from pathlib import Path
import platform
import subprocess
import time
from build import compiler

ROOT = Path(__file__).resolve().parent.parent

class Memory(C.Structure):
    _fields_ = [("cb", W.DWORD), ("PageFaultCount", W.DWORD)] + [(name, C.c_size_t) for name in (
        "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage",
        "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage", "PrivateUsage")]

def capture(argv):
    return subprocess.check_output([str(v) for v in argv], cwd=ROOT, encoding="utf-8", errors="replace").strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("small", "fast"), default="small")
    args = parser.parse_args()
    if os.name != "nt": parser.error("This window-memory measurement tool requires Windows; run the native bench binary on Linux/macOS")
    kernel = C.WinDLL("kernel32", use_last_error=True)
    user = C.WinDLL("user32", use_last_error=True)
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]; kernel.OpenProcess.restype = W.HANDLE
    kernel.CloseHandle.argtypes = [W.HANDLE]
    kernel.K32GetProcessMemoryInfo.argtypes = [W.HANDLE, C.POINTER(Memory), W.DWORD]
    kernel.GetProcessTimes.argtypes = [W.HANDLE] + [C.POINTER(W.FILETIME)] * 4
    callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    user.EnumWindows.argtypes = [callback_type, W.LPARAM]
    user.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
    user.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
    def cpu_ns(handle):
        times = [W.FILETIME() for _ in range(4)]
        if not kernel.GetProcessTimes(handle, *(C.byref(t) for t in times)):
            raise C.WinError(C.get_last_error())
        return sum(((t.dwHighDateTime << 32) | t.dwLowDateTime) * 100 for t in times[2:])
    report = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "platform": platform.platform(), "processor": platform.processor(), "mode": args.mode, "renderer": "d2d",
              "gcc": capture([compiler(None, "MYGOOSE_CC", "gcc"), "-dumpfullversion"]), "windows": {},
              "headless": capture([ROOT/"build"/args.mode/"bench.exe"]).splitlines()}
    for name in ("counter", "gallery", "list", "quotes", "events", "editor"):
        exe = ROOT/"build"/args.mode/f"{name}.exe"
        env = {k:v for k,v in os.environ.items() if k != "MYGOOSE_DUMP"}
        env["MYGOOSE_HIDDEN"] = "1"
        p = subprocess.Popen([str(exe)], cwd=ROOT, env=env, creationflags=subprocess.CREATE_NO_WINDOW)
        handle = kernel.OpenProcess(0x410, False, p.pid)
        try:
            time.sleep(0.4)
            if p.poll() is not None: raise RuntimeError(f"{name} exited: {p.returncode}")
            before = cpu_ns(handle); time.sleep(0.6); after = cpu_ns(handle)
            memory = Memory(); memory.cb = C.sizeof(memory)
            if not kernel.K32GetProcessMemoryInfo(handle, C.byref(memory), memory.cb): raise C.WinError(C.get_last_error())
            data = {"exe_bytes": exe.stat().st_size, "working_set_bytes": memory.WorkingSetSize,
                    "private_bytes": memory.PrivateUsage, "cpu_ms_in_600ms": (after-before)/1e6}
            report["windows"][name] = data
            print(f"{name}: {data}", flush=True)
        finally:
            @callback_type
            def close(hwnd, _):
                pid = W.DWORD(); user.GetWindowThreadProcessId(hwnd, C.byref(pid))
                if pid.value == p.pid: user.PostMessageW(hwnd, 0x10, 0, 0)
                return True
            user.EnumWindows(close, 0)
            try: p.wait(timeout=3)
            except subprocess.TimeoutExpired: p.terminate(); p.wait(timeout=3)
            if handle: kernel.CloseHandle(handle)
    out = ROOT/"build"/args.mode/"measurements-d2d.json"
    out.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print("\n".join(report["headless"]))
    print(f"Saved {out}")

if __name__ == "__main__": main()
