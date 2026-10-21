#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/statvfs.h>
#include <sys/utsname.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <signal.h>
#include <spawn.h>
#include <errno.h>
#include "sample.h"

static uint64_t mon_old_user, mon_old_system, mon_old_idle, mon_old_rx, mon_old_tx, mon_old_read, mon_old_write;
static bool mon_initialized, mon_cpu_ready, mon_net_ready, mon_disk_ready;
static long mon_hz, mon_page;
static double mon_now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static pid_t mon_file_manager;
void mon_set_gpu_active(bool enabled) {
    (void)enabled;
    mon_metrics[MON_GPU_STATE] = mon_metrics[MON_GPU_MEMORY_STATE] = -1;
}
static void mon_reap_file_manager(void) {
    if (mon_file_manager > 0 && waitpid(mon_file_manager, NULL, WNOHANG) != 0) mon_file_manager = 0;
}
static void mon_shutdown(void) { mon_reap_file_manager(); }
static void mon_init(void) {
    mon_hz = sysconf(_SC_CLK_TCK); mon_page = sysconf(_SC_PAGESIZE);
    mon_metrics[MON_CORES] = sysconf(_SC_NPROCESSORS_ONLN); mon_metrics[MON_SELF_PID] = getpid();
    gethostname(mon_host, sizeof mon_host - 1); strcpy(mon_disk, "/");
    struct utsname u; if (!uname(&u)) snprintf(mon_os, sizeof mon_os, "Linux / %.80s", u.release);
    FILE *f = fopen("/proc/cpuinfo", "r"); char line[1024];
    if (f) {
        while (fgets(line, sizeof line, f)) if (!strncmp(line, "model name", 10) || !strncmp(line, "Hardware", 8)) {
            char *name = strchr(line, ':'); if (name) { ++name; while (*name == ' ' || *name == '\t') ++name;
                name[strcspn(name, "\r\n")] = 0; snprintf(mon_chip, sizeof mon_chip, "%.255s", name); break; }
        }
        fclose(f);
    }
    if (!mon_chip[0]) strcpy(mon_chip, "Linux processor");
    mon_initialized = true;
}
static void mon_collect(double elapsed) {
    if (!mon_initialized) mon_init();
    mon_reap_file_manager();
    FILE *f = fopen("/proc/stat", "r"); char line[8192];
    if (f) {
        unsigned long long user, nice, system, idle, wait = 0, irq = 0, soft = 0, steal = 0;
        if (fgets(line, sizeof line, f) && sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu", &user, &nice, &system, &idle, &wait, &irq, &soft, &steal) >= 4) {
            uint64_t ut = user + nice, st = system + irq + soft + steal, it = idle + wait;
            double du = mon_delta(ut, mon_old_user, 1), ds = mon_delta(st, mon_old_system, 1), di = mon_delta(it, mon_old_idle, 1);
            double total = du + ds + di;
            if (mon_cpu_ready && total > 0) { mon_metrics[MON_USER_CPU] = du / total * 100; mon_metrics[MON_SYSTEM_CPU] = ds / total * 100; mon_metrics[MON_CPU] = (du + ds) / total * 100; }
            mon_old_user = ut; mon_old_system = st; mon_old_idle = it; mon_cpu_ready = true;
        }
        if (mon_cores_enabled) while (fgets(line, sizeof line, f)) {
            unsigned id;
            user = nice = system = idle = wait = irq = soft = steal = 0;
            if (sscanf(line, "cpu%u %llu %llu %llu %llu %llu %llu %llu %llu", &id,
                &user, &nice, &system, &idle, &wait, &irq, &soft, &steal) >= 5)
                mon_core_counters(id, user + nice, system + irq + soft + steal, idle + wait);
        }
        fclose(f);
    }
    f = fopen("/proc/meminfo", "r");
    if (f) {
        double available = 0, cached = 0, reclaim = 0; char key[80]; unsigned long long value;
        while (fgets(line, sizeof line, f)) if (sscanf(line, "%79s %llu", key, &value) == 2) {
            double bytes = value * 1024.0;
            if (!strcmp(key, "MemTotal:")) mon_metrics[MON_MEM_TOTAL] = bytes;
            else if (!strcmp(key, "MemAvailable:")) available = bytes;
            else if (!strcmp(key, "Cached:")) cached = bytes;
            else if (!strcmp(key, "SReclaimable:")) reclaim = bytes;
            else if (!strcmp(key, "Committed_AS:")) mon_metrics[MON_COMMIT_USED] = bytes;
            else if (!strcmp(key, "CommitLimit:")) mon_metrics[MON_COMMIT_LIMIT] = bytes;
        }
        mon_metrics[MON_MEM_FREE] = available; mon_metrics[MON_MEM_USED] = fmax(0, mon_metrics[MON_MEM_TOTAL] - available);
        mon_metrics[MON_MEM_CACHE] = cached + reclaim; fclose(f);
    }
    struct statvfs disk;
    if (!statvfs("/", &disk)) { mon_metrics[MON_DISK_FREE] = (double)disk.f_bavail * disk.f_frsize; mon_metrics[MON_DISK_TOTAL] = (double)disk.f_blocks * disk.f_frsize; }
    f = fopen("/proc/diskstats", "r"); uint64_t read = 0, write = 0; mon_metrics[MON_DISK_OK] = 0;
    if (f) {
        while (fgets(line, sizeof line, f)) {
            unsigned major, minor; char name[128], path[256];
            unsigned long long reads, merged, sectors, ms, writes, wmerged, wsectors;
            if (sscanf(line, "%u %u %127s %llu %llu %llu %llu %llu %llu %llu", &major, &minor, name, &reads, &merged, &sectors, &ms, &writes, &wmerged, &wsectors) != 10) continue;
            /* Whole physical devices only: no partitions, loopbacks, dm or md layers. */
            snprintf(path, sizeof path, "/sys/block/%s/device", name);
            if (access(path, F_OK)) continue;
            read += sectors * 512; write += wsectors * 512; mon_metrics[MON_DISK_OK] = 1;
        }
        fclose(f);
        if (mon_disk_ready) { mon_metrics[MON_DISK_READ] = mon_delta(read, mon_old_read, elapsed); mon_metrics[MON_DISK_WRITE] = mon_delta(write, mon_old_write, elapsed); }
        mon_old_read = read; mon_old_write = write; mon_disk_ready = true;
    } else mon_disk_ready = false;
    f = fopen("/proc/net/dev", "r"); uint64_t rx = 0, tx = 0; mon_metrics[MON_NET_OK] = 0;
    if (f) {
        while (fgets(line, sizeof line, f)) {
            char name[128]; unsigned long long in, out;
            if (sscanf(line, " %127[^:]: %llu %*u %*u %*u %*u %*u %*u %*u %llu", name, &in, &out) != 3) continue;
            if (!strcmp(name, "lo") || !strncmp(name, "veth", 4) || !strncmp(name, "docker", 6) || !strncmp(name, "br-", 3) || !strncmp(name, "tun", 3) || !strncmp(name, "tap", 3)) continue;
            rx += in; tx += out;
        }
        fclose(f);
        if (mon_net_ready) { mon_metrics[MON_NET_IN] = mon_delta(rx, mon_old_rx, elapsed); mon_metrics[MON_NET_OUT] = mon_delta(tx, mon_old_tx, elapsed); }
        mon_old_rx = rx; mon_old_tx = tx; mon_net_ready = true; mon_metrics[MON_NET_OK] = 1;
    } else mon_net_ready = false;
    DIR *dir = opendir("/proc"); struct dirent *entry;
    if (dir) {
        while ((entry = readdir(dir))) {
            char *end; unsigned long pid = strtoul(entry->d_name, &end, 10);
            if (!pid || *end || pid > UINT32_MAX) continue;
            char path[96]; snprintf(path, sizeof path, "/proc/%lu/stat", pid);
            f = fopen(path, "r"); if (!f) continue;
            if (!fgets(line, sizeof line, f)) { fclose(f); continue; } fclose(f);
            char *first = strchr(line, '('), *last = strrchr(line, ')'); if (!first || !last || last <= first) continue;
            if (mon_count == MON_CAP) { ++mon_metrics[MON_OMITTED]; continue; }
            mon_process *p = &mon_rows[mon_count++]; memset(p, 0, sizeof *p); p->pid = (uint32_t)pid;
            size_t n = (size_t)(last - first - 1); if (n >= sizeof p->name) n = sizeof p->name - 1;
            memcpy(p->name, first + 1, n); p->name[n] = 0;
            char *save = NULL, *token = strtok_r(last + 2, " ", &save); int field = 3;
            while (token) {
                if (field == 14 || field == 15) p->ticks += strtoull(token, NULL, 10);
                else if (field == 20) p->threads = (uint32_t)strtoul(token, NULL, 10);
                else if (field == 22) p->birth = strtoull(token, NULL, 10);
                else if (field == 23) p->private_memory = strtoull(token, NULL, 10);
                else if (field == 24) { long long rss = strtoll(token, NULL, 10); p->memory = rss > 0 ? (uint64_t)rss * mon_page : 0; }
                token = strtok_r(NULL, " ", &save); ++field;
            }
            p->known = field > 24; mon_metrics[MON_THREADS] += p->threads;
            if (p->known) ++mon_metrics[MON_READABLE];
            mon_process_rate(p, elapsed, (double)mon_hz);
        }
        closedir(dir);
    }
    f = fopen("/proc/uptime", "r"); if (f) { if (fgets(line, sizeof line, f)) mon_metrics[MON_UPTIME] = strtod(line, NULL); fclose(f); }
}
static uint64_t mon_linux_birth(uint32_t pid) {
    char path[96], stat[4096]; snprintf(path, sizeof path, "/proc/%u/stat", pid);
    FILE *f = fopen(path, "r"); if (!f) return 0;
    bool ok = fgets(stat, sizeof stat, f) != NULL; fclose(f); if (!ok) return 0;
    char *end = strrchr(stat, ')'), *save = NULL; if (!end || end[1] != ' ') return 0;
    char *token = strtok_r(end + 2, " ", &save);
    for (int field = 3; token && field < 22; ++field) token = strtok_r(NULL, " ", &save);
    return token ? strtoull(token, NULL, 10) : 0;
}
static void mon_read_io(mon_process *p) {
    if (!p->birth || mon_linux_birth(p->pid)!=p->birth) return;
    char path[96],line[256]; snprintf(path,sizeof path,"/proc/%u/io",p->pid);
    FILE *f=fopen(path,"r"); if (!f) return;
    unsigned long long value; uint64_t read=0,write=0; bool have_read=false,have_write=false;
    while (fgets(line,sizeof line,f)) {
        if (sscanf(line,"read_bytes: %llu",&value)==1) { read=value; have_read=true; }
        else if (sscanf(line,"write_bytes: %llu",&value)==1) { write=value; have_write=true; }
    }
    fclose(f);
    if (have_read && have_write && mon_linux_birth(p->pid)==p->birth) {
        p->io_known=true; p->io_read=read; p->io_write=write;
    }
}
static int64_t mon_read_path(const mon_process *p, mg_bytes out) {
    char path[96], buffer[4096]; snprintf(path, sizeof path, "/proc/%u/exe", p->pid);
    ssize_t n = readlink(path, buffer, sizeof buffer);
    /* A reused PID must not attach a new executable to an old selection. */
    if (n <= 0 || !p->birth || mon_linux_birth(p->pid) != p->birth) return 0;
    return mon_copy((mg_string){(const uint8_t *)buffer,n}, out);
}
static int32_t mon_action_errno(int error) {
    return error == ESRCH || error == ENOENT ? MON_ACTION_GONE :
        error == EPERM || error == EACCES ? MON_ACTION_DENIED :
        error == ENOSYS ? MON_ACTION_UNSUPPORTED : MON_ACTION_FAILED;
}
int32_t mon_control_process(int64_t pid, uint64_t birth, bool force) {
    if (pid <= 1 || pid > INT32_MAX) return MON_ACTION_CRITICAL;
    if (!birth) return MON_ACTION_UNVERIFIED;
#if defined(SYS_pidfd_open) && defined(SYS_pidfd_send_signal)
    int fd = (int)syscall(SYS_pidfd_open, (pid_t)pid, 0);
    if (fd < 0) return mon_action_errno(errno);
    int32_t result = MON_ACTION_GONE;
    if (mon_linux_birth((uint32_t)pid) == birth) {
        /* Signal the pinned process, never a numeric PID checked earlier. */
        result = syscall(SYS_pidfd_send_signal, fd, force ? SIGKILL : SIGTERM, NULL, 0) == 0 ? MON_ACTION_OK : mon_action_errno(errno);
    }
    close(fd); return result;
#else
    (void)force; return MON_ACTION_UNSUPPORTED;
#endif
}
#ifndef MON_SPAWN_DIRECTORY
#define MON_SPAWN_DIRECTORY posix_spawnp
#endif
int32_t mon_reveal_file(mg_string path) {
    if (path.len <= 1 || path.len >= 4096 || path.data[0] != '/' || memchr(path.data, 0, (size_t)path.len)) return MON_ACTION_BAD_PATH;
    char directory[4096]; memcpy(directory, path.data, (size_t)path.len); directory[path.len] = 0;
    char *last = strrchr(directory, '/'); if (last == directory) last[1] = 0; else *last = 0;
    mon_reap_file_manager(); if (mon_file_manager > 0) return MON_ACTION_BUSY;
    char *argv[] = {"xdg-open", directory, NULL}; extern char **environ;
    int error = MON_SPAWN_DIRECTORY(&mon_file_manager, "xdg-open", NULL, NULL, argv, environ);
    if (error) { mon_file_manager = 0; return error == ENOENT ? MON_ACTION_UNSUPPORTED : mon_action_errno(error); }
    return MON_ACTION_OK;
}
