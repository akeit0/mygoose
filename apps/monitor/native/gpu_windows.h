#ifndef MYGOOSE_MONITOR_GPU_WINDOWS_H
#define MYGOOSE_MONITOR_GPU_WINDOWS_H
#include <wchar.h>
/* App-owned, vendor-neutral WDDM counters. No graphics device or vendor SDK.
   Sum process contributions per physical engine, then report the busiest one. */
#define MON_GPU_ENGINE_CAP 128
#define MON_GPU_BUFFER_CAP (2u*1024*1024)
typedef struct { unsigned high, low, physical, engine, pid; double usage; } mon_gpu_engine;
static mon_gpu_engine mon_gpu_engines[MON_GPU_ENGINE_CAP];
static int mon_gpu_engine_count;
static PDH_HQUERY mon_gpu_query;
static PDH_HCOUNTER mon_gpu_counter, mon_gpu_dedicated_counter, mon_gpu_shared_counter;
static uint8_t *mon_gpu_buffer;
static DWORD mon_gpu_buffer_size;
static bool mon_gpu_active;
static double mon_gpu_retry_at, mon_gpu_memory_retry_at;
#define MON_GPU_RETRY_SECONDS 30.0
#ifndef MON_GPU_OPEN_QUERY
#define MON_GPU_OPEN_QUERY(out) PdhOpenQueryW(NULL,0,out)
#endif
static void mon_gpu_close(void) {
    if (mon_gpu_query) PdhCloseQuery(mon_gpu_query);
    mon_gpu_query = NULL; mon_gpu_counter = mon_gpu_dedicated_counter = mon_gpu_shared_counter = NULL;
    free(mon_gpu_buffer); mon_gpu_buffer = NULL; mon_gpu_buffer_size = 0;
    mon_gpu_retry_at = mon_gpu_memory_retry_at = 0;
}
static void mon_gpu_retry(double now) {
    mon_gpu_close(); mon_gpu_retry_at = now+MON_GPU_RETRY_SECONDS;
}
void mon_set_gpu_active(bool active) {
    if (!active && mon_gpu_active) mon_gpu_close();
    if (!active || active != mon_gpu_active) {
        mon_metrics[MON_GPU_STATE] = mon_metrics[MON_GPU_MEMORY_STATE] = active ? 0 : -1;
        for (int i = 0; i < mon_count; ++i) mon_rows[i].gpu_known = false;
    }
    mon_gpu_active = active;
}
static double mon_gpu_reading(DWORD status, double value) {
    return (status == PDH_CSTATUS_VALID_DATA || status == PDH_CSTATUS_NEW_DATA) && isfinite(value) && value >= 0 ? value : -1;
}
/* Instance names have a fixed ASCII grammar. Parse without scanf's format
   machinery on every process/engine, with checked 32-bit numeric fields. */
static bool mon_gpu_number(const wchar_t **cursor, const wchar_t *prefix, unsigned base, unsigned *value) {
    const wchar_t *p = *cursor;
    while (*prefix) { if (*p++ != *prefix++) return false; }
    unsigned result = 0, digits = 0;
    for (;;) {
        unsigned digit = *p >= L'0' && *p <= L'9' ? (unsigned)(*p-L'0') :
            *p >= L'a' && *p <= L'f' ? (unsigned)(*p-L'a'+10) :
            *p >= L'A' && *p <= L'F' ? (unsigned)(*p-L'A'+10) : base;
        if (digit >= base) break;
        if (result > (UINT32_MAX-digit)/base) return false;
        result = result*base+digit; ++digits; ++p;
    }
    if (!digits) return false;
    *value = result; *cursor = p; return true;
}
static bool mon_gpu_key(const wchar_t *name, bool engine, mon_gpu_engine *key) {
    const wchar_t *p = name;
    if (engine && !mon_gpu_number(&p,L"pid_",10,&key->pid)) return false;
    if (!mon_gpu_number(&p,engine ? L"_luid_0x" : L"luid_0x",16,&key->high) ||
        !mon_gpu_number(&p,L"_0x",16,&key->low) || !mon_gpu_number(&p,L"_phys_",10,&key->physical)) return false;
    if (!engine) return !*p;
    if (!mon_gpu_number(&p,L"_eng_",10,&key->engine)) return false;
    const wchar_t *suffix = L"_engtype_";
    while (*suffix) { if (*p++ != *suffix++) return false; }
    return *p != 0;
}
/* The provider supplies one utilization counter per process/physical engine.
   Only attribute an interval to a process whose birth matches both snapshots;
   a new/reused or inaccessible PID must not inherit another process's rate. */
static void mon_gpu_processes_begin(void) {
    for (int i = 0; i < mon_count; ++i) {
        mon_process *p = &mon_rows[i]; p->gpu = 0; p->gpu_known = false;
        if (p->birth) for (int j = 0; j < mon_previous_count; ++j) {
            if (mon_previous[j].pid == p->pid && mon_previous[j].birth == p->birth) { p->gpu_known = true; break; }
        }
    }
}
static void mon_gpu_process_reading(unsigned pid, double usage) {
    for (int i = 0; i < mon_count; ++i) if (mon_rows[i].pid == pid) {
        mon_process *p = &mon_rows[i];
        if (usage < 0) p->gpu_known = false;
        else p->gpu = fmin(100,fmax(p->gpu,usage));
        break;
    }
}
static void mon_gpu_processes_clear(void) {
    for (int i = 0; i < mon_count; ++i) mon_rows[i].gpu_known = false;
}
static bool mon_gpu_add_engine(const wchar_t *name, double usage) {
    mon_gpu_engine key = {0}; if (!mon_gpu_key(name,true,&key)) return false;
    mon_gpu_process_reading(key.pid,usage);
    if (usage < 0) return true;
    for (int i = 0; i < mon_gpu_engine_count; ++i) {
        mon_gpu_engine *entry = &mon_gpu_engines[i];
        if (entry->high == key.high && entry->low == key.low && entry->physical == key.physical && entry->engine == key.engine) {
            entry->usage += usage; return true;
        }
    }
    if (mon_gpu_engine_count == MON_GPU_ENGINE_CAP) return false;
    key.usage = usage; mon_gpu_engines[mon_gpu_engine_count++] = key; return true;
}
static double mon_gpu_busiest(void) {
    double value = 0;
    for (int i = 0; i < mon_gpu_engine_count; ++i) value = fmax(value,mon_gpu_engines[i].usage);
    return fmin(100,value);
}
/* Reuse one aligned allocation across all three counter arrays. Cap growth
   and retries so driver/process churn cannot allocate without a bound. */
static bool mon_gpu_array(PDH_HCOUNTER counter, bool engine, double *total) {
    if (!counter) return false;
    for (int attempt = 0; attempt < 3; ++attempt) {
        DWORD bytes = mon_gpu_buffer_size, count = 0;
        PDH_STATUS status = PdhGetFormattedCounterArrayW(counter,PDH_FMT_DOUBLE|PDH_FMT_NOCAP100,&bytes,&count,(PDH_FMT_COUNTERVALUE_ITEM_W *)mon_gpu_buffer);
        if (status == (PDH_STATUS)PDH_MORE_DATA) {
            if (bytes > MON_GPU_BUFFER_CAP-65536) return false;
            DWORD next = bytes+65536;
            if (next <= mon_gpu_buffer_size) return false;
            void *buffer = realloc(mon_gpu_buffer,next); if (!buffer) return false;
            mon_gpu_buffer = buffer; mon_gpu_buffer_size = next; continue;
        }
        if (status != ERROR_SUCCESS || bytes > mon_gpu_buffer_size || count > bytes/sizeof(PDH_FMT_COUNTERVALUE_ITEM_W)) return false;
        const PDH_FMT_COUNTERVALUE_ITEM_W *items = (const void *)mon_gpu_buffer;
        bool valid = false; *total = 0;
        for (DWORD i = 0; i < count; ++i) {
            const wchar_t *name = items[i].szName;
            uintptr_t start = (uintptr_t)name, base = (uintptr_t)mon_gpu_buffer;
            if (start < base || start-base >= bytes || (start-base)%sizeof(wchar_t) || !wmemchr(name,0,(bytes-(start-base))/sizeof(wchar_t))) return false;
            double value = mon_gpu_reading(items[i].FmtValue.CStatus,items[i].FmtValue.doubleValue);
            mon_gpu_engine key = {0};
            if (engine) { if (!mon_gpu_add_engine(name,value)) return false; }
            else if (value >= 0) { if (!mon_gpu_key(name,false,&key)) return false; *total += value; }
            if (value >= 0) valid = true;
        }
        return valid;
    }
    return false;
}
static void mon_collect_gpu(void) {
    if (!mon_gpu_active) return;
    mon_metrics[MON_GPU_STATE] = mon_metrics[MON_GPU_MEMORY_STATE] = -1;
    mon_gpu_processes_clear();
    double now = mon_now();
    bool warmup = false;
    if (!mon_gpu_query) {
        if (now < mon_gpu_retry_at) return;
        if (MON_GPU_OPEN_QUERY(&mon_gpu_query) != ERROR_SUCCESS) { mon_gpu_retry(now); return; }
        if (PdhAddEnglishCounterW(mon_gpu_query,L"\\GPU Engine(*)\\Utilization Percentage",0,&mon_gpu_counter) != ERROR_SUCCESS) {
            mon_gpu_retry(now); return;
        }
        warmup = true;
    }
    if ((!mon_gpu_dedicated_counter || !mon_gpu_shared_counter) && now >= mon_gpu_memory_retry_at) {
        mon_gpu_memory_retry_at = now+MON_GPU_RETRY_SECONDS;
        if (!mon_gpu_dedicated_counter && PdhAddEnglishCounterW(mon_gpu_query,L"\\GPU Adapter Memory(*)\\Dedicated Usage",0,&mon_gpu_dedicated_counter) != ERROR_SUCCESS) mon_gpu_dedicated_counter = NULL;
        if (!mon_gpu_shared_counter && PdhAddEnglishCounterW(mon_gpu_query,L"\\GPU Adapter Memory(*)\\Shared Usage",0,&mon_gpu_shared_counter) != ERROR_SUCCESS) mon_gpu_shared_counter = NULL;
    }
    if (PdhCollectQueryData(mon_gpu_query) != ERROR_SUCCESS) { mon_gpu_retry(now); return; }
    mon_gpu_engine_count = 0;
    double dedicated = 0, shared = 0, unused = 0;
    if (warmup) mon_metrics[MON_GPU_STATE] = 0;
    else {
        mon_gpu_processes_begin();
        if (mon_gpu_array(mon_gpu_counter,true,&unused)) {
            mon_metrics[MON_GPU] = mon_gpu_busiest(); mon_metrics[MON_GPU_STATE] = 1;
        } else mon_gpu_processes_clear();
    }
    bool dedicated_ok = mon_gpu_array(mon_gpu_dedicated_counter,false,&dedicated);
    bool shared_ok = mon_gpu_array(mon_gpu_shared_counter,false,&shared);
    if (dedicated_ok && shared_ok) {
        mon_metrics[MON_GPU_DEDICATED] = dedicated; mon_metrics[MON_GPU_SHARED] = shared; mon_metrics[MON_GPU_MEMORY_STATE] = 1;
    }
}
#endif
