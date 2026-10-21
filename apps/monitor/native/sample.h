#ifndef MYGOOSE_MONITOR_SAMPLE_H
#define MYGOOSE_MONITOR_SAMPLE_H
#include "../../../native/backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* Application-only storage; linking MyGoose itself does not include this. */
#define MON_CAP 4096
_Static_assert(MON_CAP<=UINT16_MAX,"Monitor query indices must fit in 16 bits");
#define MON_HISTORY 3600
#define MON_MEMORY_UNKNOWN UINT64_MAX
enum { MON_ACTION_OK = 1, MON_ACTION_GONE = -1, MON_ACTION_DENIED = -2, MON_ACTION_NO_WINDOW = -3,
       MON_ACTION_UNVERIFIED = -4, MON_ACTION_CRITICAL = -5, MON_ACTION_FAILED = -6,
       MON_ACTION_UNSUPPORTED = -7, MON_ACTION_BUSY = -8, MON_ACTION_BAD_PATH = -9 };
enum { MON_CPU, MON_USER_CPU, MON_SYSTEM_CPU, MON_MEM_USED, MON_MEM_TOTAL, MON_MEM_FREE, MON_MEM_CACHE,
       MON_COMMIT_USED, MON_COMMIT_LIMIT, MON_DISK_READ, MON_DISK_WRITE, MON_DISK_FREE, MON_DISK_TOTAL,
       MON_NET_IN, MON_NET_OUT, MON_PROCESSES, MON_THREADS, MON_UPTIME, MON_CORES, MON_SAMPLE_MS, MON_READABLE,
       MON_DISK_OK, MON_NET_OK, MON_SELF_PID, MON_OMITTED,
       MON_GPU, MON_GPU_STATE, MON_GPU_DEDICATED, MON_GPU_SHARED, MON_GPU_MEMORY_STATE, MON_METRIC_COUNT };
typedef struct {
    uint32_t pid, threads;
    uint64_t birth, ticks, memory, private_memory, io_read, io_write;
    double cpu, seconds, read_rate, write_rate, gpu, io_time;
    bool known, io_known, gpu_known, io_rate_known;
    char name[256];
} mon_process;
static mon_process mon_rows[MON_CAP], mon_previous[MON_CAP];
static int mon_count, mon_previous_count, mon_visible;
static const uint16_t *mon_order;
static double mon_metrics[MON_METRIC_COUNT], mon_last;
static float mon_hist[8][MON_HISTORY];
static int mon_head, mon_samples;
static int64_t mon_epoch;
/* Two queries cover Overview's CPU/memory rankings and the active table.
   16-bit row indices keep both orders within the former single int order's
   storage. Search keys are copied, never retained from Goose's frame arena. */
typedef struct {
    uint16_t order[MON_CAP]; uint8_t search[4096];
    int64_t epoch; uint64_t used; int length,count,sort; bool ascending,valid;
} mon_query_cache;
static mon_query_cache mon_queries[2];
static uint64_t mon_query_clock;
static char mon_host[256], mon_chip[256], mon_os[128], mon_disk[64];
#include "cores.h"
static double mon_now(void);
static void mon_collect(double elapsed);
static void mon_shutdown(void);
static int64_t mon_read_path(const mon_process *p, mg_bytes out);
static void mon_read_io(mon_process *p);
static void mon_detail_io(mon_process *p);

static double mon_delta(uint64_t now, uint64_t before, double elapsed) {
    return now >= before && elapsed > 0 ? (double)(now - before) / elapsed : 0;
}
static void mon_io_rate(mon_process *p,const mon_process *old,double elapsed) {
    p->io_rate_known=false;
    if (!p->io_known || !old->io_known) return;
    /* Detail reads can happen between sampling ticks. Their own observation
       times, rather than the global CPU interval, define the I/O rate. */
    double interval=p->io_time>0 && old->io_time>0 ? p->io_time-old->io_time :
        !p->io_time && !old->io_time ? elapsed : 0;
    if (interval<=0) return;
    p->read_rate=mon_delta(p->io_read,old->io_read,interval);
    p->write_rate=mon_delta(p->io_write,old->io_write,interval); p->io_rate_known=true;
}
/* PID + creation time handles PID reuse. First sightings have no MON_CPU rate. */
static void mon_process_rate(mon_process *p, double elapsed, double tick_hz) {
    if (!p->known) return;
    p->seconds = p->ticks / tick_hz;
    for (int i = 0; i < mon_previous_count; ++i) {
        const mon_process *old = &mon_previous[i];
        if (old->pid == p->pid && old->birth == p->birth && old->known) {
            p->cpu = mon_delta(p->ticks, old->ticks, elapsed) * 100 / tick_hz;
            mon_io_rate(p,old,elapsed);
            return;
        }
    }
}
bool mon_sample(void) {
    double start = mon_now(), elapsed = mon_last ? start - mon_last : 0;
    if (mon_last && elapsed < .1) return false;
    mon_previous_count = mon_count;
    memcpy(mon_previous, mon_rows, sizeof(mon_process) * (size_t)mon_count);
    mon_count = 0;
    mon_metrics[MON_THREADS] = mon_metrics[MON_READABLE] = mon_metrics[MON_OMITTED] = 0;
    mon_cores_begin(); mon_collect(elapsed); mon_cores_end();
    mon_last = start;
    ++mon_epoch;
    mon_metrics[MON_PROCESSES] = mon_count + mon_metrics[MON_OMITTED];
    mon_metrics[MON_SAMPLE_MS] = (mon_now() - start) * 1000;
    /* The initial snapshot has no interval; don't plot a fabricated idle MON_CPU. */
    if (elapsed > 0) {
        const double values[8] = { mon_metrics[MON_CPU], mon_metrics[MON_MEM_TOTAL] > 0 ?
            mon_metrics[MON_MEM_USED] / mon_metrics[MON_MEM_TOTAL] * 100 : 0,
            mon_metrics[MON_DISK_READ], mon_metrics[MON_DISK_WRITE], mon_metrics[MON_NET_IN],
            mon_metrics[MON_NET_OUT], mon_metrics[MON_PROCESSES],
            mon_metrics[MON_GPU_STATE] == 1 ? mon_metrics[MON_GPU] : -1 };
        for (int i = 0; i < 8; ++i) mon_hist[i][mon_head] = (float)values[i];
        mon_head = (mon_head + 1) % MON_HISTORY;
        if (mon_samples < MON_HISTORY) ++mon_samples;
    }
    return true;
}
double mon_value(int32_t field) { return field >= 0 && field < MON_METRIC_COUNT ? mon_metrics[field] : 0; }
static double mon_field(const mon_process *p, int32_t field) {
    switch (field) {
    case 0: return p->pid; case 1: return p->cpu;
    case 2: return p->memory == MON_MEMORY_UNKNOWN ? 0 : (double)p->memory;
    case 3: return p->threads; case 4: return p->seconds; case 5: return p->known;
    case 6: return (double)p->private_memory; case 7: return (double)p->io_read; case 8: return (double)p->io_write;
    case 9: return p->io_known; case 10: return p->read_rate; case 11: return p->write_rate;
    case 12: return p->known && p->memory != MON_MEMORY_UNKNOWN;
    case 13: return p->gpu_known ? p->gpu : 0; case 14: return p->gpu_known;
    case 15: return p->io_rate_known;
    default: return 0;
    }
}
double mon_process_value(int32_t row, int32_t field) {
    if (row<0 || row>=mon_visible) return 0;
    mon_process *p=&mon_rows[mon_order[row]];
    if ((field>=7 && field<=11) || field==15) mon_detail_io(p);
    return mon_field(p,field);
}
int32_t mon_find_process(int64_t pid, uint64_t birth) {
    for (int i = 0; i < mon_count; ++i) if (mon_rows[i].pid == pid && mon_rows[i].birth == birth) return i;
    return -1;
}
static void mon_detail_io(mon_process *p) {
    if (!p->birth || p->io_time>0) return;
    p->io_known=p->io_rate_known=false; p->read_rate=p->write_rate=0;
    mon_read_io(p); p->io_time=mon_now(); // Cache success and failure for this snapshot.
    if (!p->io_known) return;
    for (int i=0;i<mon_previous_count;i++) {
        const mon_process *old=&mon_previous[i];
        if (old->pid==p->pid && old->birth==p->birth) { mon_io_rate(p,old,0); break; }
    }
}
double mon_detail_value(int32_t row, int32_t field) {
    if (row<0 || row>=mon_count) return 0;
    mon_process *p=&mon_rows[row];
    if ((field>=7 && field<=11) || field==15) mon_detail_io(p);
    return mon_field(p,field);
}
uint64_t mon_detail_birth(int32_t row) { return row >= 0 && row < mon_count ? mon_rows[row].birth : 0; }
int64_t mon_generation(void) { return mon_epoch; }
uint64_t mon_process_birth(int32_t row) {
    return row >= 0 && row < mon_visible ? mon_rows[mon_order[row]].birth : 0;
}
static mg_string mon_string(const char *s) { return (mg_string){(const uint8_t *)s, (int64_t)strlen(s)}; }
mg_string mon_name(int32_t row) {
    return mon_string(row >= 0 && row < mon_visible ? mon_rows[mon_order[row]].name : "");
}
mg_string mon_info(int32_t field) {
    if (field >= 6 && field <= 9) {
#ifdef __APPLE__
        const char *labels[] = {"Swap Utilization", "Swap used", "Swap allocated", "Used swap / currently allocated swap"};
#else
        const char *labels[] = {"Commit Utilization", "Committed", "Commit limit", "Committed bytes / system commit limit"};
#endif
        return mon_string(labels[field - 6]);
    }
    if (field == 5) {
#ifdef _WIN32
        return mon_string("Private working set");
#else
        return mon_string("Resident memory");
#endif
    }
    if (field == 4) {
#ifdef _WIN32
        return mon_string("Private commit");
#else
        return mon_string("Virtual memory");
#endif
    }
    return mon_string(field == 0 ? mon_host : field == 1 ? mon_chip : field == 2 ? mon_os : mon_disk);
}
static int mon_sort_key, mon_sort_direction;
static int mon_compare(const void *a, const void *b) {
    const mon_process *x = &mon_rows[*(const uint16_t *)a], *y = &mon_rows[*(const uint16_t *)b];
    bool x_known = mon_sort_key == 6 ? x->gpu_known : mon_sort_key == 2 ? mon_field(x,12) != 0 : x->known;
    bool y_known = mon_sort_key == 6 ? y->gpu_known : mon_sort_key == 2 ? mon_field(y,12) != 0 : y->known;
    if (((mon_sort_key >= 1 && mon_sort_key <= 3) || mon_sort_key == 6) && x_known != y_known) return x_known ? -1 : 1;
    double xv = mon_sort_key == 1 ? x->cpu : mon_sort_key == 2 ? mon_field(x,2) :
        mon_sort_key == 3 ? x->seconds : mon_sort_key == 4 ? x->threads : mon_sort_key == 6 ? mon_field(x,13) : x->pid;
    double yv = mon_sort_key == 1 ? y->cpu : mon_sort_key == 2 ? mon_field(y,2) :
        mon_sort_key == 3 ? y->seconds : mon_sort_key == 4 ? y->threads : mon_sort_key == 6 ? mon_field(y,13) : y->pid;
    int order = mon_sort_key == 0 ? strcmp(x->name, y->name) : (xv > yv) - (xv < yv);
    return order ? order * mon_sort_direction : (x->pid > y->pid) - (x->pid < y->pid);
}
static unsigned char mon_lower(unsigned char c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
static bool mon_contains(const char *s, mg_string needle) {
    size_t len = strlen(s);
    if (needle.len < 0 || (uint64_t)needle.len > len) return false;
    for (size_t i = 0; i + (size_t)needle.len <= len; ++i) {
        int64_t j = 0;
        while (j < needle.len && mon_lower((unsigned char)s[i + (size_t)j]) == mon_lower(needle.data[j])) ++j;
        if (j == needle.len) return true;
    }
    return false;
}
/* Filter changes only the index array. The raw snapshot retains PID identity. */
int32_t mon_query(mg_string search, int32_t sort, bool ascending) {
    mon_visible=0;
    if (search.len<0 || search.len>4096 || (search.len && !search.data)) return 0;
    uint64_t tick=++mon_query_clock; int oldest=0;
    for (int i=0;i<2;i++) {
        mon_query_cache *q=&mon_queries[i];
        if (q->valid && q->epoch==mon_epoch && q->sort==sort && q->ascending==ascending &&
            q->length==search.len && (!search.len || !memcmp(q->search,search.data,(size_t)search.len))) {
            q->used=tick; mon_order=q->order; mon_visible=q->count; return mon_visible;
        }
        if (q->used<mon_queries[oldest].used) oldest=i;
    }
    mon_query_cache *q=&mon_queries[oldest];
    mon_sort_key = sort; mon_sort_direction = ascending ? 1 : -1;
    for (int i = 0; i < mon_count; ++i) {
        bool match=!search.len || mon_contains(mon_rows[i].name,search);
        if (!match) { char pid[32]; snprintf(pid,sizeof pid,"%u",mon_rows[i].pid); match=mon_contains(pid,search); }
        if (match) q->order[mon_visible++] = (uint16_t)i;
    }
    qsort(q->order,(size_t)mon_visible,sizeof q->order[0],mon_compare);
    if (search.len) memcpy(q->search,search.data,(size_t)search.len);
    q->epoch=mon_epoch; q->used=tick; q->length=(int)search.len; q->count=mon_visible;
    q->sort=sort; q->ascending=ascending; q->valid=true; mon_order=q->order;
    return mon_visible;
}
/* Right-aligned, averaged buckets; never invent history before the first sample. */
double mon_history(int32_t series, int32_t bucket, int32_t buckets, int32_t span) {
    if (series < 0 || series >= 8 || bucket < 0 || bucket >= buckets || buckets < 1) return -1;
    if (span < buckets) span = buckets;
    if (span > MON_HISTORY) span = MON_HISTORY;
    int begin = bucket * span / buckets, end = (bucket + 1) * span / buckets;
    int available = mon_samples < span ? mon_samples : span;
    if (end <= span - available) return -1;
    if (begin < span - available) begin = span - available;
    double value = 0; int readings = 0;
    for (int i = begin; i < end; ++i) {
        float sample = mon_hist[series][(mon_head - span + i + MON_HISTORY) % MON_HISTORY];
        if (sample >= 0) { value += sample; ++readings; }
    }
    return readings ? value / readings : -1;
}
int32_t mon_history_count(void) { return mon_samples; }
mg_string mon_format(double value, int32_t style) {
    static char buffers[16][96]; static unsigned slot;
    char *out = buffers[slot++ % 16];
    if (style == 1 || style == 2) {
        const char *units[] = {"B", "KiB", "MiB", "GiB", "TiB"}; int u = 0;
        while (value >= 1024 && u < 4) { value /= 1024; ++u; }
        snprintf(out, 96, value >= 100 || u == 0 ? "%.0f %s%s" : "%.1f %s%s", value, units[u], style == 2 ? "/s" : "");
    } else if (style == 3) snprintf(out, 96, "%.1f%%", value);
    else if (style == 4) { uint64_t n = (uint64_t)fmax(value, 0); snprintf(out, 96, "%llu:%02llu:%02llu",
        (unsigned long long)(n / 3600), (unsigned long long)(n / 60 % 60), (unsigned long long)(n % 60)); }
    else if (style == 5) snprintf(out, 96, "%.1f ms", value);
    else snprintf(out, 96, "%.0f", value);
    return mon_string(out);
}
void mon_close(void) {
    mon_shutdown(); mon_cores_close();
    memset(mon_queries,0,sizeof mon_queries); mon_query_clock=0; mon_visible=0; mon_order=NULL;
}
static int64_t mon_copy(mg_string s, mg_bytes out) {
    int64_t n = s.len < out.len ? s.len : out.len;
    if (n < 0) return 0;
    while (n > 0 && n < s.len && (s.data[n] & 0xc0) == 0x80) --n;
    if (n) memcpy(out.data, s.data, (size_t)n);
    return n;
}
int64_t mon_write_name(int32_t row, mg_bytes out) { return mon_copy(mon_name(row), out); }
int64_t mon_write_detail_name(int32_t row, mg_bytes out) { return mon_copy(mon_string(row >= 0 && row < mon_count ? mon_rows[row].name : ""), out); }
int64_t mon_write_detail_path(int32_t row, mg_bytes out) { return row >= 0 && row < mon_count ? mon_read_path(&mon_rows[row], out) : 0; }
int64_t mon_write_info(int32_t field, mg_bytes out) { return mon_copy(mon_info(field), out); }
int64_t mon_write_format(double value, int32_t style, mg_bytes out) { return mon_copy(mon_format(value, style), out); }
#endif
