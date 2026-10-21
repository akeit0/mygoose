#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <winsock2.h>
#include <ws2ipdef.h>
#include <windows.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <shlobj.h>
#include <winternl.h>
#include <stddef.h>
#include "sample.h"

static uint64_t mon_idle, mon_kernel, mon_user;
typedef struct { uint64_t luid, rx, tx; } mon_adapter;
static mon_adapter mon_adapters[128];
static int mon_adapter_count;
static PDH_HQUERY mon_pdh;
static PDH_HCOUNTER mon_read_counter, mon_write_counter;
static PDH_HQUERY mon_core_query;
static PDH_HCOUNTER mon_core_counter;
static bool mon_core_query_attempted;
static bool mon_initialized, mon_net_ready, mon_cpu_ready;
static wchar_t mon_root[MAX_PATH];
typedef NTSTATUS (NTAPI *mon_query_system_fn)(SYSTEM_INFORMATION_CLASS, PVOID, ULONG, PULONG);
static mon_query_system_fn mon_query_system;
static bool mon_query_system_checked;
static uint8_t *mon_process_buffer;
static ULONG mon_process_buffer_size;
static double mon_now(void) {
    LARGE_INTEGER now; static LARGE_INTEGER frequency;
    if (!frequency.QuadPart) QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&now); return now.QuadPart / (double)frequency.QuadPart;
}
static uint64_t mon_filetime(FILETIME t) { return ((uint64_t)t.dwHighDateTime << 32) | t.dwLowDateTime; }
/* PROCESS_MEMORY_COUNTERS_EX2's documented layout, also usable with MinGW
   headers that only declare EX. PrivateUsage is commit, not private residency. */
typedef struct {
    PROCESS_MEMORY_COUNTERS_EX counters;
    SIZE_T private_working_set;
    ULONG64 shared_commit;
} mon_memory_counters;
#ifndef MON_PROCESS_MEMORY_INFO
#define MON_PROCESS_MEMORY_INFO(process, counters, bytes) GetProcessMemoryInfo(process, counters, bytes)
#endif
static bool mon_read_memory(HANDLE process, mon_process *p) {
    mon_memory_counters pm = { .counters = { .cb = sizeof pm }, .private_working_set = SIZE_MAX };
    if (!MON_PROCESS_MEMORY_INFO(process,(PROCESS_MEMORY_COUNTERS *)&pm,sizeof pm)) {
        /* Older Windows can still supply commit and CPU/time. Never substitute
           total working set or committed bytes for unavailable private RAM. */
        memset(&pm,0,sizeof pm); pm.counters.cb = sizeof pm.counters; pm.private_working_set = SIZE_MAX;
        if (!MON_PROCESS_MEMORY_INFO(process,(PROCESS_MEMORY_COUNTERS *)&pm.counters,sizeof pm.counters)) return false;
    }
    p->memory = pm.private_working_set == SIZE_MAX ? MON_MEMORY_UNKNOWN : pm.private_working_set;
    p->private_memory = pm.counters.PrivateUsage;
    return true;
}
#include "gpu_windows.h"
static void mon_read_io(mon_process *p) {
    if (!p->birth) return;
    HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|PROCESS_VM_READ,FALSE,p->pid);
    if (!process) process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,p->pid);
    if (!process) return;
    FILETIME birth,ended,kernel,user; IO_COUNTERS io;
    /* The handle pins identity across the read, including numeric PID reuse. */
    if (GetProcessTimes(process,&birth,&ended,&kernel,&user) && mon_filetime(birth)==p->birth && GetProcessIoCounters(process,&io)) {
        p->io_known=true; p->io_read=io.ReadTransferCount; p->io_write=io.WriteTransferCount;
    }
    CloseHandle(process);
}
static void mon_shutdown(void) {
    if (mon_pdh) { PdhCloseQuery(mon_pdh); mon_pdh = NULL; }
    if (mon_core_query) { PdhCloseQuery(mon_core_query); mon_core_query = NULL; }
    mon_core_query_attempted = false;
    mon_gpu_close();
    free(mon_process_buffer); mon_process_buffer = NULL; mon_process_buffer_size = 0;
}
static void mon_collect_process(DWORD pid, DWORD threads, const wchar_t *name, int length, double elapsed) {
    if (!pid) return; /* Idle pseudo-process is not a task. */
    mon_metrics[MON_THREADS] += threads;
    if (mon_count == MON_CAP) { ++mon_metrics[MON_OMITTED]; return; }
    mon_process *p = &mon_rows[mon_count++]; memset(p,0,sizeof *p);
    p->pid = pid; p->threads = threads;
    if (length) WideCharToMultiByte(CP_UTF8,0,name,length,p->name,sizeof p->name-1,NULL,NULL);
    if (!p->name[0]) snprintf(p->name,sizeof p->name,"Process %lu",(unsigned long)pid);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,FALSE,pid);
    if (!process) process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);
    if (!process) return;
    FILETIME birth, ended, kernel, user;
    bool times = GetProcessTimes(process,&birth,&ended,&kernel,&user) != 0;
    if (times) { p->birth = mon_filetime(birth); p->ticks = mon_filetime(kernel)+mon_filetime(user); }
    if (times && mon_read_memory(process,p)) {
        p->known = true; ++mon_metrics[MON_READABLE]; mon_process_rate(p,elapsed,10000000.0);
    }
    CloseHandle(process);
}
/* Only use the documented metadata prefix: all counters and creation times
   still come from the existing per-process APIs, including private working set. */
static bool mon_process_snapshot_valid(const void *data, ULONG bytes) {
    if (!data) return false;
    const size_t minimum = offsetof(SYSTEM_PROCESS_INFORMATION,UniqueProcessId)+sizeof(HANDLE);
    const uint8_t *buffer = data;
    for (size_t offset = 0; ; ) {
        if (offset > bytes || bytes-offset < minimum) return false;
        const SYSTEM_PROCESS_INFORMATION *p = (const void *)(buffer+offset);
        uintptr_t name = (uintptr_t)p->ImageName.Buffer, base = (uintptr_t)buffer;
        if ((uintptr_t)p->UniqueProcessId > UINT32_MAX || p->ImageName.Length % sizeof(wchar_t) ||
            p->ImageName.Length > p->ImageName.MaximumLength) return false;
        if (p->ImageName.Length && (name < base || name-base > bytes || p->ImageName.Length > bytes-(name-base))) return false;
        if (!p->NextEntryOffset) return true;
        if (p->NextEntryOffset < minimum || p->NextEntryOffset % sizeof(void *) || p->NextEntryOffset > bytes-offset) return false;
        offset += p->NextEntryOffset;
    }
}
static bool mon_collect_process_snapshot(double elapsed) {
    if (!mon_query_system_checked) {
        mon_query_system_checked = true;
        mon_query_system = (mon_query_system_fn)(void *)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtQuerySystemInformation");
    }
    if (!mon_query_system) return false;
    for (int attempt = 0; attempt < 4; ++attempt) {
        ULONG needed = 0;
        NTSTATUS status = mon_query_system(SystemProcessInformation,mon_process_buffer,mon_process_buffer_size,&needed);
        if (status == (NTSTATUS)0xc0000004L || status == (NTSTATUS)0xc0000023L) {
            /* Reuse the allocation across samples; leave slack for process churn. */
            ULONG next = needed > mon_process_buffer_size ? needed : mon_process_buffer_size;
            if (next > 16u*1024*1024-65536) return false;
            next += 65536;
            void *buffer = realloc(mon_process_buffer,next); if (!buffer) return false;
            mon_process_buffer = buffer; mon_process_buffer_size = next; continue;
        }
        if (status < 0 || needed > mon_process_buffer_size || !mon_process_snapshot_valid(mon_process_buffer,needed)) return false;
        for (size_t offset = 0; ; ) {
            const SYSTEM_PROCESS_INFORMATION *p = (const void *)(mon_process_buffer+offset);
            mon_collect_process((DWORD)(uintptr_t)p->UniqueProcessId,p->NumberOfThreads,p->ImageName.Buffer,p->ImageName.Length/sizeof(wchar_t),elapsed);
            if (!p->NextEntryOffset) break;
            offset += p->NextEntryOffset;
        }
        return true;
    }
    return false;
}
static void mon_collect_process_toolhelp(double elapsed) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    if (snapshot == INVALID_HANDLE_VALUE) return;
    PROCESSENTRY32W entry = { .dwSize = sizeof entry };
    if (Process32FirstW(snapshot,&entry)) do {
        mon_collect_process(entry.th32ProcessID,entry.cntThreads,entry.szExeFile,(int)wcslen(entry.szExeFile),elapsed);
    } while (Process32NextW(snapshot,&entry));
    CloseHandle(snapshot);
}
/* Processor Information instances are numeric pairs; totals are excluded.
   IDs come from the provider, never from array order or localized names. */
static bool mon_core_instance(const wchar_t *name, uint32_t *id) {
    if (!name || *name < L'0' || *name > L'9') return false;
    uint32_t pair[2] = {0,0};
    for (int part = 0; part < 2; ++part) {
        if (*name < L'0' || *name > L'9') return false;
        while (*name >= L'0' && *name <= L'9') { pair[part] = pair[part] * 10 + (uint32_t)(*name++ - L'0'); if (pair[part] > 65535) return false; }
        if (part == 0 && *name++ != L',') return false;
    }
    if (*name) return false;
    *id = pair[0] * 65536 + pair[1]; return true;
}
static double mon_core_pdh_value(DWORD status, double value) {
    if ((status != PDH_CSTATUS_VALID_DATA && status != PDH_CSTATUS_NEW_DATA) || !isfinite(value)) return -1;
    /* Idle-accounting granularity can make a valid busy percentage slightly
       negative. A valid idle interval is zero, not a missing reading. */
    return fmax(0, fmin(100, value));
}
static void mon_collect_cores(void) {
    if (!mon_cores_enabled) return;
    if (!mon_core_query_attempted) {
        mon_core_query_attempted = true;
        if (PdhOpenQueryW(NULL, 0, &mon_core_query) == ERROR_SUCCESS &&
            PdhAddEnglishCounterW(mon_core_query, L"\\Processor Information(*)\\% Processor Time", 0, &mon_core_counter) == ERROR_SUCCESS) {
            /* Warmup is different from an unavailable provider. */
            if (PdhCollectQueryData(mon_core_query) == ERROR_SUCCESS) mon_cores_attempted = false;
        }
        else if (mon_core_query) { PdhCloseQuery(mon_core_query); mon_core_query = NULL; }
        return;
    }
    if (!mon_core_query || PdhCollectQueryData(mon_core_query) != ERROR_SUCCESS) return;
    union { PDH_FMT_COUNTERVALUE_ITEM_W alignment; uint8_t bytes[65536]; } buffer;
    DWORD bytes = 0, count = 0;
    PDH_STATUS status = PdhGetFormattedCounterArrayW(mon_core_counter, PDH_FMT_DOUBLE, &bytes, &count, NULL);
    for (int attempt = 0; attempt < 2 && status == (PDH_STATUS)PDH_MORE_DATA && bytes <= sizeof buffer && bytes > 0; ++attempt)
        status = PdhGetFormattedCounterArrayW(mon_core_counter, PDH_FMT_DOUBLE, &bytes, &count, (PDH_FMT_COUNTERVALUE_ITEM_W *)buffer.bytes);
    if (status != ERROR_SUCCESS || count > sizeof buffer / sizeof(PDH_FMT_COUNTERVALUE_ITEM_W)) return;
    const PDH_FMT_COUNTERVALUE_ITEM_W *items = (const PDH_FMT_COUNTERVALUE_ITEM_W *)buffer.bytes;
    for (DWORD i = 0; i < count; ++i) {
        uint32_t id;
        if (mon_core_instance(items[i].szName, &id)) {
            mon_core_update(id, mon_core_pdh_value(items[i].FmtValue.CStatus, items[i].FmtValue.doubleValue));
        }
    }
}
static void mon_init(void) {
    mon_metrics[MON_CORES] = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    mon_metrics[MON_SELF_PID] = GetCurrentProcessId();
    DWORD len = sizeof mon_host; GetComputerNameA(mon_host, &len);
    strcpy(mon_os, "Windows / native DirectWrite");
    DWORD bytes = sizeof mon_chip;
    if (RegGetValueA(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        "ProcessorNameString", RRF_RT_REG_SZ, NULL, mon_chip, &bytes) != ERROR_SUCCESS) strcpy(mon_chip, "Processor");
    wchar_t windows[MAX_PATH]; GetWindowsDirectoryW(windows, MAX_PATH);
    if (!GetVolumePathNameW(windows, mon_root, MAX_PATH)) wcscpy(mon_root, L"C:\\");
    WideCharToMultiByte(CP_UTF8, 0, mon_root, -1, mon_disk, sizeof mon_disk, NULL, NULL);
    if (PdhOpenQueryW(NULL, 0, &mon_pdh) == ERROR_SUCCESS) {
        if (PdhAddEnglishCounterW(mon_pdh, L"\\PhysicalDisk(_Total)\\Disk Read Bytes/sec", 0, &mon_read_counter) == ERROR_SUCCESS &&
            PdhAddEnglishCounterW(mon_pdh, L"\\PhysicalDisk(_Total)\\Disk Write Bytes/sec", 0, &mon_write_counter) == ERROR_SUCCESS)
            PdhCollectQueryData(mon_pdh);
        else mon_shutdown();
    }
    mon_initialized = true;
}
static void mon_collect(double elapsed) {
    if (!mon_initialized) mon_init();
    mon_collect_cores();
    FILETIME idle, kernel, user;
    if (GetSystemTimes(&idle, &kernel, &user)) {
        uint64_t i = mon_filetime(idle), k = mon_filetime(kernel), u = mon_filetime(user);
        double total = (double)(k - mon_kernel) + (double)(u - mon_user);
        if (mon_cpu_ready && total > 0 && k >= mon_kernel && u >= mon_user && i >= mon_idle) {
            mon_metrics[MON_USER_CPU] = (u - mon_user) * 100.0 / total;
            mon_metrics[MON_SYSTEM_CPU] = fmax(0, (double)(k - mon_kernel) - (double)(i - mon_idle)) * 100.0 / total;
            mon_metrics[MON_CPU] = fmin(100, mon_metrics[MON_USER_CPU] + mon_metrics[MON_SYSTEM_CPU]);
        }
        mon_idle = i; mon_kernel = k; mon_user = u; mon_cpu_ready = true;
    }
    MEMORYSTATUSEX mem = { .dwLength = sizeof mem };
    if (GlobalMemoryStatusEx(&mem)) {
        mon_metrics[MON_MEM_TOTAL] = (double)mem.ullTotalPhys; mon_metrics[MON_MEM_FREE] = (double)mem.ullAvailPhys;
        mon_metrics[MON_MEM_USED] = (double)(mem.ullTotalPhys - mem.ullAvailPhys);
    }
    PERFORMANCE_INFORMATION perf = { .cb = sizeof perf };
    if (GetPerformanceInfo(&perf, sizeof perf)) {
        mon_metrics[MON_MEM_CACHE] = (double)perf.SystemCache * perf.PageSize;
        mon_metrics[MON_COMMIT_USED] = (double)perf.CommitTotal * perf.PageSize;
        mon_metrics[MON_COMMIT_LIMIT] = (double)perf.CommitLimit * perf.PageSize;
    }
    ULARGE_INTEGER free_bytes, total_bytes;
    if (GetDiskFreeSpaceExW(mon_root, NULL, &total_bytes, &free_bytes)) {
        mon_metrics[MON_DISK_FREE] = (double)free_bytes.QuadPart; mon_metrics[MON_DISK_TOTAL] = (double)total_bytes.QuadPart;
    }
    mon_metrics[MON_DISK_OK] = 0;
    if (mon_pdh && elapsed > 0 && PdhCollectQueryData(mon_pdh) == ERROR_SUCCESS) {
        PDH_FMT_COUNTERVALUE read, write;
        if (PdhGetFormattedCounterValue(mon_read_counter, PDH_FMT_DOUBLE, NULL, &read) == ERROR_SUCCESS &&
            PdhGetFormattedCounterValue(mon_write_counter, PDH_FMT_DOUBLE, NULL, &write) == ERROR_SUCCESS &&
            (read.CStatus == PDH_CSTATUS_VALID_DATA || read.CStatus == PDH_CSTATUS_NEW_DATA) &&
            (write.CStatus == PDH_CSTATUS_VALID_DATA || write.CStatus == PDH_CSTATUS_NEW_DATA)) {
            mon_metrics[MON_DISK_READ] = fmax(0, read.doubleValue); mon_metrics[MON_DISK_WRITE] = fmax(0, write.doubleValue);
            mon_metrics[MON_DISK_OK] = 1;
        }
    }
    MIB_IF_TABLE2 *table = NULL; double rx = 0, tx = 0; mon_adapter next[128]; int next_count = 0;
    mon_metrics[MON_NET_OK] = 0;
    if (GetIfTable2(&table) == NO_ERROR) {
        for (ULONG n = 0; n < table->NumEntries; ++n) {
            MIB_IF_ROW2 *r = &table->Table[n];
            if (r->InterfaceAndOperStatusFlags.HardwareInterface && r->OperStatus == IfOperStatusUp &&
                r->Type != IF_TYPE_SOFTWARE_LOOPBACK && r->Type != IF_TYPE_TUNNEL && next_count < 128) {
                if (mon_net_ready) for (int i = 0; i < mon_adapter_count; ++i) if (mon_adapters[i].luid == r->InterfaceLuid.Value) {
                    rx += mon_delta(r->InOctets, mon_adapters[i].rx, elapsed);
                    tx += mon_delta(r->OutOctets, mon_adapters[i].tx, elapsed); break;
                }
                next[next_count++] = (mon_adapter){ r->InterfaceLuid.Value, r->InOctets, r->OutOctets };
            }
        }
        FreeMibTable(table);
        mon_metrics[MON_NET_IN] = rx; mon_metrics[MON_NET_OUT] = tx;
        memcpy(mon_adapters, next, sizeof(mon_adapter) * (size_t)next_count); mon_adapter_count = next_count;
        mon_net_ready = true; mon_metrics[MON_NET_OK] = 1;
    } else mon_net_ready = false;
    if (!mon_collect_process_snapshot(elapsed)) mon_collect_process_toolhelp(elapsed);
    mon_collect_gpu();
    mon_metrics[MON_UPTIME] = GetTickCount64() / 1000.0;
}
static int64_t mon_read_path(const mon_process *p, mg_bytes out) {
    if (!p->birth) return 0;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, p->pid); if (!process) return 0;
    wchar_t path[1024]; char utf8[4096]; DWORD length = 1024; FILETIME birth, exit_time, kernel, user;
    bool same = GetProcessTimes(process, &birth, &exit_time, &kernel, &user) && mon_filetime(birth) == p->birth;
    bool ok = same && QueryFullProcessImageNameW(process, 0, path, &length); CloseHandle(process);
    if (!ok) return 0;
    int bytes = WideCharToMultiByte(CP_UTF8, 0, path, (int)length, utf8, sizeof utf8, NULL, NULL);
    return bytes > 0 ? mon_copy((mg_string){(const uint8_t *)utf8,bytes}, out) : 0;
}

typedef struct { DWORD pid; HANDLE process; int posted, denied; } mon_close_request;
static BOOL CALLBACK mon_close_window(HWND window, LPARAM data) {
    mon_close_request *r = (mon_close_request *)data; DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid == r->pid && !GetWindow(window, GW_OWNER) && WaitForSingleObject(r->process, 0) == WAIT_TIMEOUT) {
        if (PostMessageW(window, WM_CLOSE, 0, 0)) ++r->posted;
        else if (GetLastError() == ERROR_ACCESS_DENIED) ++r->denied;
    }
    return TRUE;
}
int32_t mon_control_process(int64_t pid, uint64_t birth, bool force) {
    if (pid <= 4 || pid > UINT32_MAX) return MON_ACTION_CRITICAL;
    if (!birth) return MON_ACTION_UNVERIFIED;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE | (force ? PROCESS_TERMINATE : 0), FALSE, (DWORD)pid);
    if (!process) return GetLastError() == ERROR_INVALID_PARAMETER ? MON_ACTION_GONE : MON_ACTION_DENIED;
    FILETIME created, ended, kernel, user; int32_t result = MON_ACTION_DENIED;
    if (GetProcessTimes(process, &created, &ended, &kernel, &user)) {
        if (mon_filetime(created) != birth || WaitForSingleObject(process, 0) != WAIT_TIMEOUT) result = MON_ACTION_GONE;
        else {
            typedef BOOL (WINAPI *critical_fn)(HANDLE, PBOOL);
            critical_fn is_critical = (critical_fn)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "IsProcessCritical");
            BOOL critical = TRUE;
            if (!is_critical) result = MON_ACTION_UNSUPPORTED;
            else if (!is_critical(process, &critical)) result = MON_ACTION_DENIED;
            else if (critical) result = MON_ACTION_CRITICAL;
            else if (force) result = TerminateProcess(process, 1) ? MON_ACTION_OK : MON_ACTION_DENIED;
            else {
                mon_close_request request = { .pid = (DWORD)pid, .process = process };
                BOOL enumerated = EnumWindows(mon_close_window, (LPARAM)&request);
                result = request.posted ? MON_ACTION_OK : request.denied ? MON_ACTION_DENIED : enumerated ? MON_ACTION_NO_WINDOW : MON_ACTION_FAILED;
            }
        }
    }
    CloseHandle(process); return result;
}
#ifndef MON_SELECT_ITEM
#define MON_SELECT_ITEM(item) SHOpenFolderAndSelectItems(item, 0, NULL, 0)
#endif
int32_t mon_reveal_file(mg_string path) {
    if (path.len <= 0 || path.len >= 4096 || memchr(path.data, 0, (size_t)path.len)) return MON_ACTION_BAD_PATH;
    wchar_t wide[4096]; int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path.data, (int)path.len, wide, 4095);
    if (!n) return MON_ACTION_BAD_PATH;
    wide[n] = 0;
    if (!((n >= 3 && wide[1] == ':' && (wide[2] == '\\' || wide[2] == '/')) || (n >= 2 && wide[0] == '\\' && wide[1] == '\\'))) return MON_ACTION_BAD_PATH;
    HRESULT init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(init) && init != RPC_E_CHANGED_MODE) return MON_ACTION_FAILED;
    PIDLIST_ABSOLUTE item = NULL;
    HRESULT result = SHParseDisplayName(wide, NULL, &item, 0, NULL);
    if (SUCCEEDED(result)) { result = MON_SELECT_ITEM(item); CoTaskMemFree(item); }
    if (SUCCEEDED(init)) CoUninitialize();
    return SUCCEEDED(result) ? MON_ACTION_OK : MON_ACTION_BAD_PATH;
}
