/* App-owned Darwin counters; no privileged helper or external commands. */
#include <time.h>
#include <unistd.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <spawn.h>
#include <errno.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOBlockStorageDriver.h>
#include "sample.h"

static bool mon_initialized, mon_cpu_ready, mon_net_ready, mon_disk_ready;
static uint64_t mon_old_user, mon_old_system, mon_old_idle, mon_old_rx, mon_old_tx, mon_old_read, mon_old_write;
static mach_port_t mon_host_port;
static double mon_tick_hz;
static pid_t mon_file_manager;
static double mon_now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
void mon_set_gpu_active(bool enabled) {
    (void)enabled; mon_metrics[MON_GPU_STATE] = mon_metrics[MON_GPU_MEMORY_STATE] = -1;
}
static void mon_reap_file_manager(void) {
    if (mon_file_manager > 0 && waitpid(mon_file_manager, NULL, WNOHANG) != 0) mon_file_manager = 0;
}
static void mon_shutdown(void) {
    mon_reap_file_manager();
    if (mon_host_port) mach_port_deallocate(mach_task_self(), mon_host_port);
    mon_host_port = 0; mon_initialized = mon_cpu_ready = mon_net_ready = mon_disk_ready = false;
}
static void mon_sys_string(const char *key, char *out, size_t capacity) {
    size_t size = capacity;
    if (sysctlbyname(key, out, &size, NULL, 0)) out[0] = 0;
    out[capacity - 1] = 0;
}
static void mon_init(void) {
    mon_host_port = mach_host_self();
    mach_timebase_info_data_t timebase={1,1}; mach_timebase_info(&timebase);
    mon_tick_hz=1e9*timebase.denom/timebase.numer;
    mon_metrics[MON_SELF_PID] = getpid();
    gethostname(mon_host, sizeof mon_host - 1); strcpy(mon_disk, "/System/Volumes/Data");
    mon_sys_string("machdep.cpu.brand_string", mon_chip, sizeof mon_chip);
    if (!mon_chip[0]) mon_sys_string("hw.model", mon_chip, sizeof mon_chip);
    char version[80]; mon_sys_string("kern.osproductversion", version, sizeof version);
    snprintf(mon_os, sizeof mon_os, "macOS %s", version);
    mon_set_gpu_active(false); mon_initialized = true;
}
static void mon_cpu(void) {
    natural_t cpus = 0; processor_info_array_t info = NULL; mach_msg_type_number_t count = 0;
    if (host_processor_info(mon_host_port, PROCESSOR_CPU_LOAD_INFO, &cpus, &info, &count) != KERN_SUCCESS) return;
    uint64_t user = 0, system = 0, idle = 0;
    processor_cpu_load_info_t loads = (processor_cpu_load_info_t)info;
    for (natural_t i = 0; i < cpus; ++i) {
        uint64_t u = (uint32_t)loads[i].cpu_ticks[CPU_STATE_USER] + (uint64_t)(uint32_t)loads[i].cpu_ticks[CPU_STATE_NICE];
        uint64_t s = (uint32_t)loads[i].cpu_ticks[CPU_STATE_SYSTEM], d = (uint32_t)loads[i].cpu_ticks[CPU_STATE_IDLE];
        user += u; system += s; idle += d;
        if (mon_cores_enabled) mon_core_counters(i, u, s, d);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    double du = mon_delta(user, mon_old_user, 1), ds = mon_delta(system, mon_old_system, 1), di = mon_delta(idle, mon_old_idle, 1);
    double total = du + ds + di;
    if (mon_cpu_ready && total > 0) {
        mon_metrics[MON_USER_CPU] = du * 100 / total; mon_metrics[MON_SYSTEM_CPU] = ds * 100 / total;
        mon_metrics[MON_CPU] = (du + ds) * 100 / total;
    }
    mon_old_user = user; mon_old_system = system; mon_old_idle = idle; mon_cpu_ready = true;
    mon_metrics[MON_CORES] = cpus;
}
static void mon_memory(void) {
    uint64_t total = 0; size_t size = sizeof total;
    if (!sysctlbyname("hw.memsize", &total, &size, NULL, 0)) mon_metrics[MON_MEM_TOTAL] = (double)total;
    vm_statistics64_data_t vm; mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0;
    if (host_page_size(mon_host_port, &page) == KERN_SUCCESS &&
        host_statistics64(mon_host_port, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        /* Match Activity Monitor's app + wired + compressed view. Purgeable
           and external file-backed pages remain reclaimable. */
        double used_pages = fmax(0, (double)vm.active_count + vm.inactive_count - vm.external_page_count - vm.purgeable_count);
        double used = (used_pages + vm.wire_count + vm.compressor_page_count) * page;
        mon_metrics[MON_MEM_USED] = fmin(mon_metrics[MON_MEM_TOTAL], used);
        mon_metrics[MON_MEM_FREE] = mon_metrics[MON_MEM_TOTAL] - mon_metrics[MON_MEM_USED];
        mon_metrics[MON_MEM_CACHE] = ((double)vm.external_page_count + vm.purgeable_count) * page;
    }
    /* Darwin has no Windows-style commit limit. These fields display swap
       with platform-specific labels supplied by mon_info. */
    struct xsw_usage swap; size = sizeof swap;
    if (!sysctlbyname("vm.swapusage", &swap, &size, NULL, 0)) {
        mon_metrics[MON_COMMIT_USED] = (double)swap.xsu_used; mon_metrics[MON_COMMIT_LIMIT] = (double)swap.xsu_total;
    }
    struct timeval boot; size = sizeof boot;
    if (!sysctlbyname("kern.boottime", &boot, &size, NULL, 0)) mon_metrics[MON_UPTIME] = difftime(time(NULL), boot.tv_sec);
}
static bool mon_number(CFDictionaryRef dict, CFStringRef key, uint64_t *out) {
    CFTypeRef value = CFDictionaryGetValue(dict, key); int64_t number = 0;
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID() || !CFNumberGetValue(value, kCFNumberSInt64Type, &number) || number < 0) return false;
    *out = (uint64_t)number; return true;
}
static void mon_disk_sample(double elapsed) {
    struct statfs disk;
    if (!statfs(mon_disk, &disk)) {
        mon_metrics[MON_DISK_FREE] = (double)disk.f_bavail * disk.f_bsize;
        mon_metrics[MON_DISK_TOTAL] = (double)disk.f_blocks * disk.f_bsize;
    }
    io_iterator_t iterator = 0; bool available = false; uint64_t read = 0, write = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOBlockStorageDriverClass), &iterator) == KERN_SUCCESS) {
        io_object_t device;
        while ((device = IOIteratorNext(iterator))) {
            CFTypeRef stats = IORegistryEntryCreateCFProperty(device, CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, 0);
            if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
                uint64_t r = 0, w = 0;
                if (mon_number(stats, CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey), &r) &&
                    mon_number(stats, CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey), &w)) {
                    read += r; write += w; available = true;
                }
            }
            if (stats) CFRelease(stats);
            IOObjectRelease(device);
        }
        IOObjectRelease(iterator);
    }
    mon_metrics[MON_DISK_OK] = available;
    mon_metrics[MON_DISK_READ] = available && mon_disk_ready ? mon_delta(read, mon_old_read, elapsed) : 0;
    mon_metrics[MON_DISK_WRITE] = available && mon_disk_ready ? mon_delta(write, mon_old_write, elapsed) : 0;
    mon_old_read = read; mon_old_write = write; mon_disk_ready = available;
}
static void mon_network(double elapsed) {
    /* getifaddrs exposes 32-bit byte totals on Darwin; IFINFO2 has 64-bit
       counters so a busy connection does not wrap every four GiB. */
    static union { uint64_t alignment; char bytes[262144]; } buffer;
    int mib[] = {CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, 0};
    size_t size = sizeof buffer.bytes; uint64_t rx = 0, tx = 0;
    bool available = sysctl(mib, 6, buffer.bytes, &size, NULL, 0) == 0;
    if (available) {
        for (size_t offset = 0; offset + sizeof(struct if_msghdr) <= size;) {
            const struct if_msghdr *header = (const void *)(buffer.bytes + offset);
            if (!header->ifm_msglen || header->ifm_msglen > size - offset) { available = false; break; }
            if (header->ifm_type == RTM_IFINFO2 && header->ifm_msglen >= sizeof(struct if_msghdr2) + offsetof(struct sockaddr_dl, sdl_data) + 2) {
                const struct if_msghdr2 *info = (const void *)header;
                const struct sockaddr_dl *address = (const void *)(info + 1);
                if ((info->ifm_flags & IFF_UP) && !(info->ifm_flags & (IFF_LOOPBACK | IFF_POINTOPOINT)) &&
                    address->sdl_nlen >= 2 && !memcmp(address->sdl_data, "en", 2)) {
                    rx += info->ifm_data.ifi_ibytes; tx += info->ifm_data.ifi_obytes;
                }
            }
            offset += header->ifm_msglen;
        }
    }
    mon_metrics[MON_NET_OK] = available;
    mon_metrics[MON_NET_IN] = available && mon_net_ready ? mon_delta(rx, mon_old_rx, elapsed) : 0;
    mon_metrics[MON_NET_OUT] = available && mon_net_ready ? mon_delta(tx, mon_old_tx, elapsed) : 0;
    mon_old_rx = rx; mon_old_tx = tx; mon_net_ready = available;
}
static uint64_t mon_macos_birth(uint32_t pid) {
    struct proc_bsdinfo info;
    return proc_pidinfo((int)pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) == sizeof info ?
        info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec : 0;
}
#ifndef MON_PROC_PID_RUSAGE
#define MON_PROC_PID_RUSAGE proc_pid_rusage
#endif
static void mon_read_io(mon_process *p) {
    if (!p->birth || mon_macos_birth(p->pid)!=p->birth) return;
    struct rusage_info_v2 usage;
    if (!MON_PROC_PID_RUSAGE((int)p->pid,RUSAGE_INFO_V2,(rusage_info_t *)&usage) && mon_macos_birth(p->pid)==p->birth) {
        p->io_known=true; p->io_read=usage.ri_diskio_bytesread; p->io_write=usage.ri_diskio_byteswritten;
    }
}
static void mon_collect(double elapsed) {
    if (!mon_initialized) mon_init();
    mon_reap_file_manager(); mon_cpu(); mon_memory(); mon_disk_sample(elapsed); mon_network(elapsed);
    static pid_t pids[MON_CAP + 1];
    int count = proc_listallpids(pids, sizeof pids);
    if (count < 0) count = 0;
    if (count > MON_CAP) mon_metrics[MON_OMITTED] = count - MON_CAP;
    if (count > MON_CAP) count = MON_CAP;
    for (int i = 0; i < count; ++i) {
        if (pids[i] <= 0) continue;
        struct proc_bsdinfo bsd;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof bsd) != sizeof bsd) continue;
        mon_process *p = &mon_rows[mon_count++]; memset(p, 0, sizeof *p);
        p->pid = (uint32_t)pids[i]; p->birth = bsd.pbi_start_tvsec * 1000000 + bsd.pbi_start_tvusec;
        p->memory = MON_MEMORY_UNKNOWN;
        snprintf(p->name, sizeof p->name, "%.*s", (int)sizeof bsd.pbi_name, bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm);
        struct proc_taskinfo task;
        if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof task) == sizeof task && mon_macos_birth(p->pid) == p->birth) {
            p->known = true; p->ticks = task.pti_total_user + task.pti_total_system;
            p->memory = task.pti_resident_size; p->private_memory = task.pti_virtual_size;
            p->threads = (uint32_t)task.pti_threadnum;
            mon_metrics[MON_READABLE]++; mon_metrics[MON_THREADS] += p->threads;
            mon_process_rate(p, elapsed, mon_tick_hz);
        }
    }
}
static int64_t mon_read_path(const mon_process *p, mg_bytes out) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (!p->birth || proc_pidpath((int)p->pid, path, sizeof path) <= 0 || mon_macos_birth(p->pid) != p->birth) return 0;
    return mon_copy(mon_string(path), out);
}
int32_t mon_control_process(int64_t pid, uint64_t birth, bool force) {
    (void)force;
    if (pid <= 1 || pid > INT32_MAX) return MON_ACTION_CRITICAL;
    if (!birth) return MON_ACTION_UNVERIFIED;
    if (mon_macos_birth((uint32_t)pid) != birth) return MON_ACTION_GONE;
    /* There is no unprivileged pidfd-style signal API on Darwin. Refuse a
       check-then-kill race rather than risk signaling a reused numeric PID. */
    return MON_ACTION_UNSUPPORTED;
}
#ifndef MON_SPAWN_DIRECTORY
#define MON_SPAWN_DIRECTORY posix_spawn
#endif
int32_t mon_reveal_file(mg_string path) {
    if (path.len <= 1 || path.len >= PROC_PIDPATHINFO_MAXSIZE || path.data[0] != '/' || memchr(path.data, 0, (size_t)path.len)) return MON_ACTION_BAD_PATH;
    char file[PROC_PIDPATHINFO_MAXSIZE]; memcpy(file, path.data, (size_t)path.len); file[path.len] = 0;
    mon_reap_file_manager(); if (mon_file_manager > 0) return MON_ACTION_BUSY;
    char *argv[] = {"/usr/bin/open", "-R", file, NULL}; extern char **environ;
    int error = MON_SPAWN_DIRECTORY(&mon_file_manager, "/usr/bin/open", NULL, NULL, argv, environ);
    if (error) { mon_file_manager = 0; return error == ENOENT ? MON_ACTION_UNSUPPORTED : MON_ACTION_FAILED; }
    return MON_ACTION_OK;
}
