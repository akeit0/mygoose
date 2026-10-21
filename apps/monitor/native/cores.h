#ifndef MYGOOSE_MONITOR_CORES_H
#define MYGOOSE_MONITOR_CORES_H
/* App-only current percentages. Stable OS IDs survive enumeration changes;
   there are no per-processor history buffers or heap allocations. */
#define MON_CORE_CAP 128
typedef struct {
    uint32_t id;
    bool seen;
#ifndef _WIN32
    bool baseline;
#endif
    double value;
#ifndef _WIN32
    uint64_t user, system, idle;
#endif
} mon_core;
static mon_core mon_core_rows[MON_CORE_CAP];
static int mon_core_slots, mon_core_order[MON_CORE_CAP], mon_core_visible, mon_core_dropped;
static bool mon_cores_enabled, mon_cores_attempted;
void mon_enable_cores(void) { mon_cores_enabled = true; }
static void mon_cores_begin(void) {
    if (!mon_cores_enabled) return;
    mon_cores_attempted = true; mon_core_dropped = 0;
    for (int i = 0; i < mon_core_slots; ++i) { mon_core_rows[i].seen = false; mon_core_rows[i].value = -1; }
}
static mon_core *mon_core_slot(uint32_t id) {
    for (int i = 0; i < mon_core_slots; ++i) if (mon_core_rows[i].id == id) return &mon_core_rows[i];
    if (mon_core_slots == MON_CORE_CAP) { ++mon_core_dropped; return NULL; }
    mon_core *core = &mon_core_rows[mon_core_slots++];
    *core = (mon_core){ .id = id, .value = -1 };
    return core;
}
#ifdef _WIN32
static void mon_core_update(uint32_t id, double value) {
    mon_core *core = mon_core_slot(id); if (!core) return;
    core->seen = true;
    core->value = isfinite(value) && value >= 0 ? fmin(100, value) : -1;
}
#else
static void mon_core_counters(uint32_t id, uint64_t user, uint64_t system, uint64_t idle) {
    mon_core *core = mon_core_slot(id); if (!core) return;
    core->seen = true;
    if (core->baseline && user >= core->user && system >= core->system && idle >= core->idle) {
        double busy = (double)(user - core->user) + (double)(system - core->system);
        double total = busy + (double)(idle - core->idle);
        if (total > 0) core->value = fmin(100, busy * 100 / total);
    }
    core->user = user; core->system = system; core->idle = idle; core->baseline = true;
}
#endif
static void mon_cores_end(void) {
    if (!mon_cores_enabled) return;
    mon_core_visible = 0;
    for (int i = 0; i < mon_core_slots; ++i) {
        mon_core *core = &mon_core_rows[i];
        if (!core->seen) {
#ifndef _WIN32
            core->baseline = false;
#endif
            continue;
        }
        int at = mon_core_visible++;
        while (at > 0 && mon_core_rows[mon_core_order[at - 1]].id > core->id) { mon_core_order[at] = mon_core_order[at - 1]; --at; }
        mon_core_order[at] = i;
    }
}
static mon_core *mon_core_at(int32_t row) { return row >= 0 && row < mon_core_visible ? &mon_core_rows[mon_core_order[row]] : NULL; }
int32_t mon_core_count(void) { return mon_core_visible; }
int32_t mon_core_omitted(void) { return mon_core_dropped; }
int32_t mon_core_status(void) {
    if (!mon_cores_attempted) return 0;
    if (!mon_core_visible) return -1;
    for (int i = 0; i < mon_core_visible; ++i) if (mon_core_at(i)->value >= 0) return 1;
    return 0;
}
double mon_core_value(int32_t row) { mon_core *core = mon_core_at(row); return core ? core->value : -1; }
int64_t mon_core_write_label(int32_t row, mg_bytes out) {
    mon_core *core = mon_core_at(row); if (!core || !out.data || out.len <= 0) return 0;
    char text[48];
#ifdef _WIN32
    if (core->id >> 16) snprintf(text, sizeof text, "CPU %u,%u", core->id >> 16, core->id & 65535);
    else snprintf(text, sizeof text, "CPU %u", core->id & 65535);
#else
    snprintf(text, sizeof text, "CPU %u", core->id);
#endif
    int64_t length = (int64_t)strlen(text); if (length > out.len) length = out.len;
    memcpy(out.data, text, (size_t)length); return length;
}
static void mon_cores_close(void) {
    memset(mon_core_rows, 0, sizeof mon_core_rows);
    mon_core_slots = mon_core_visible = mon_core_dropped = 0;
    mon_cores_enabled = mon_cores_attempted = false;
}
#endif
