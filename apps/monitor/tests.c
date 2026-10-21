#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <winsock2.h>
#include <windows.h>
#include <shlobj.h>
#include <psapi.h>
#include <pdh.h>
static PDH_STATUS mon_test_gpu_open_query(PDH_HQUERY *out);
#define MON_GPU_OPEN_QUERY(out) mon_test_gpu_open_query(out)
static HRESULT mon_test_select(PCIDLIST_ABSOLUTE item);
static BOOL mon_test_memory_info(HANDLE process, PROCESS_MEMORY_COUNTERS *counters, DWORD bytes);
#define MON_SELECT_ITEM(item) mon_test_select(item)
#define MON_PROCESS_MEMORY_INFO(process, counters, bytes) mon_test_memory_info(process, counters, bytes)
#include "native/windows.c"
#else
#define _GNU_SOURCE
#include <spawn.h>
static int mon_test_spawn(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *, char *const[], char *const[]);
#define MON_SPAWN_DIRECTORY mon_test_spawn
#ifdef __APPLE__
#include <libproc.h>
#include <sys/resource.h>
static int mon_test_rusage(int,int,rusage_info_t *);
#define MON_PROC_PID_RUSAGE mon_test_rusage
#include "native/macos.c"
#else
#include "native/linux.c"
#endif
#endif
#include <assert.h>

#ifdef __APPLE__
static int mon_test_io_reads;
static bool mon_test_io_fail;
static int mon_test_rusage(int pid,int flavor,rusage_info_t *usage) {
    ++mon_test_io_reads;
    return mon_test_io_fail ? -1 : proc_pid_rusage(pid,flavor,usage);
}
static void lazy_io_tests(int index) {
    int reads=mon_test_io_reads;
    assert(reads==0); // Ordinary snapshots and CPU/memory queries do not fetch process I/O.
    assert(mon_detail_value(index,2)>0 && mon_test_io_reads==reads);
    assert(mon_detail_value(index,9)==1 && mon_test_io_reads==reads+1);
    assert(mon_detail_value(index,15)==0); // A first observation has totals but no rate.
    mon_detail_value(index,7); mon_detail_value(index,8); mon_detail_value(index,10);
    assert(mon_test_io_reads==reads+1);
    uint64_t birth=mon_rows[index].birth; int64_t pid=mon_rows[index].pid;
    usleep(120000); assert(mon_sample()); index=mon_find_process(pid,birth); assert(index>=0);
    assert(mon_test_io_reads==reads+1); // A new base sample still does not fetch I/O.
    assert(mon_detail_value(index,9)==1 && mon_detail_value(index,15)==1 && mon_test_io_reads==reads+2);
    // Failed and stale identities are cached for the snapshot, never borrowed
    // from another process or displayed as measured idle rates.
    mon_rows[index].io_time=0; mon_rows[index].io_known=false; mon_test_io_fail=true;
    assert(mon_detail_value(index,9)==0 && mon_detail_value(index,15)==0 && mon_test_io_reads==reads+3);
    mon_test_io_fail=false; mon_rows[index].io_time=0; mon_rows[index].birth++;
    assert(mon_detail_value(index,9)==0 && mon_test_io_reads==reads+3);
    mon_rows[index].birth=birth;
    puts("PASS: lazy I/O, immediate totals, per-snapshot success/failure caching, timed rates and stale identity rejection");
}
#endif

#ifdef _WIN32
static int mon_test_memory_mode;
static bool mon_test_gpu_fail;
static int mon_test_gpu_opens;
static PDH_STATUS mon_test_gpu_open_query(PDH_HQUERY *out) {
    ++mon_test_gpu_opens;
    return mon_test_gpu_fail ? ERROR_ACCESS_DENIED : PdhOpenQueryW(NULL,0,out);
}
static void gpu_tests(void) {
    mon_count = 4; mon_previous_count = 3; ++mon_epoch;
    mon_rows[0] = (mon_process){ .pid=1, .birth=101 };
    mon_rows[1] = (mon_process){ .pid=2, .birth=202 };
    mon_rows[2] = (mon_process){ .pid=3, .birth=303 };
    mon_rows[3] = (mon_process){ .pid=4 }; /* Unverified identity. */
    memcpy(mon_previous,mon_rows,3*sizeof *mon_rows);
    mon_previous[1].birth = 201; /* Reused PID. */
    mon_gpu_processes_begin();
    mon_gpu_engine_count = 0;
    assert(mon_gpu_add_engine(L"pid_1_luid_0x00000000_0x00011F7F_phys_0_eng_0_engtype_3D",20));
    assert(mon_gpu_add_engine(L"pid_2_luid_0x00000000_0x00011F7F_phys_0_eng_0_engtype_3D",30));
    assert(mon_gpu_add_engine(L"pid_2_luid_0x00000000_0x00011F7F_phys_0_eng_1_engtype_Copy",40));
    assert(mon_gpu_busiest() == 50 && mon_gpu_engine_count == 2);
    assert(mon_gpu_add_engine(L"pid_1_luid_0x00000000_0x00011F7F_phys_0_eng_1_engtype_Copy",5));
    assert(mon_rows[0].gpu_known && mon_rows[0].gpu == 20); /* Maximum, not sum. */
    assert(!mon_rows[1].gpu_known && !mon_rows[3].gpu_known);
    assert(mon_rows[2].gpu_known && mon_rows[2].gpu == 0); /* Idle, no GPU context. */
    mon_query(mon_string(""),6,false); assert(mon_process_value(0,0) == 1 && mon_process_value(2,14) == 0);
    mon_query(mon_string(""),6,true); assert(mon_process_value(0,0) == 3 && mon_process_value(2,14) == 0);
    mon_gpu_process_reading(1,-1); mon_gpu_process_reading(1,15); ++mon_epoch;
    assert(!mon_rows[0].gpu_known); /* One invalid engine keeps the reading unknown. */
    assert(mon_gpu_add_engine(L"pid_2_luid_0x00000000_0x000149F2_phys_0_eng_0_engtype_3D",90));
    assert(mon_gpu_busiest() == 90);
    mon_gpu_engines[0].usage = 110; assert(mon_gpu_busiest() == 100);
    assert(!mon_gpu_add_engine(L"bad instance",10));
    assert(!mon_gpu_add_engine(L"pid_4294967296_luid_0x0_0x0_phys_0_eng_0_engtype_3D",10));
    assert(mon_gpu_reading(PDH_CSTATUS_VALID_DATA,0) == 0);
    assert(mon_gpu_reading(PDH_CSTATUS_INVALID_DATA,0) == -1);
    mon_count = mon_previous_count = 0;
    mon_set_gpu_active(true); mon_test_gpu_fail = true; mon_collect_gpu();
    assert(!mon_gpu_query && mon_value(MON_GPU_STATE) == -1 && mon_gpu_retry_at > mon_now());
    int opens = mon_test_gpu_opens; mon_collect_gpu(); assert(mon_test_gpu_opens == opens);
    mon_test_gpu_fail = false; mon_gpu_retry_at = mon_now()-1; mon_collect_gpu();
    assert(mon_test_gpu_opens == opens+1); /* Recovery without page navigation. */
    Sleep(250); double start = mon_now(); mon_collect_gpu();
    printf("GPU: state %.0f, %.2f%%, dedicated %.1f MiB, shared %.1f MiB; %.2f ms collection\n",
        mon_value(MON_GPU_STATE),mon_value(MON_GPU),mon_value(MON_GPU_DEDICATED)/1048576,
        mon_value(MON_GPU_SHARED)/1048576,(mon_now()-start)*1000);
    assert(mon_value(MON_GPU_STATE) == -1 || (mon_value(MON_GPU_STATE) == 1 && mon_value(MON_GPU) >= 0 && mon_value(MON_GPU) <= 100));
    mon_set_gpu_active(false);
    assert(!mon_gpu_query && !mon_gpu_buffer && mon_value(MON_GPU_STATE) == -1);
    puts("PASS: GPU engine/process aggregation, idle/missing readings, PID reuse, sorting and inactive cleanup");
}
static BOOL mon_test_memory_info(HANDLE process, PROCESS_MEMORY_COUNTERS *counters, DWORD bytes) {
    if (!mon_test_memory_mode) return GetProcessMemoryInfo(process,counters,bytes);
    if (mon_test_memory_mode == 4 || (mon_test_memory_mode == 2 && bytes > sizeof(PROCESS_MEMORY_COUNTERS_EX))) {
        SetLastError(ERROR_INVALID_PARAMETER); return FALSE;
    }
    PROCESS_MEMORY_COUNTERS_EX basic = { .cb = sizeof basic, .WorkingSetSize = 65536, .PrivateUsage = 1048576 };
    memcpy(counters,&basic,sizeof basic);
    if (bytes == sizeof(mon_memory_counters) && mon_test_memory_mode != 3) {
        mon_memory_counters *extended = (mon_memory_counters *)counters;
        extended->counters.cb = sizeof *extended;
        extended->private_working_set = mon_test_memory_mode == 5 ? 0 : 4096;
    }
    return TRUE;
}
static void memory_tests(void) {
    mon_process p = { .known = true };
    mon_test_memory_mode = 1; assert(mon_read_memory(GetCurrentProcess(),&p));
    assert(p.memory == 4096 && p.private_memory == 1048576 && mon_field(&p,12)==1);
    mon_test_memory_mode = 5; assert(mon_read_memory(GetCurrentProcess(),&p));
    assert(p.memory == 0 && mon_field(&p,12)==1); /* Valid zero is not missing. */
    for (int mode = 2; mode <= 3; ++mode) {
        mon_test_memory_mode = mode; assert(mon_read_memory(GetCurrentProcess(),&p));
        assert(mon_field(&p,12)==0 && mon_field(&p,2)==0 && p.private_memory==1048576 && p.known);
    }
    mon_test_memory_mode = 4; assert(!mon_read_memory(GetCurrentProcess(),&p));
    mon_test_memory_mode = 0;
    mon_memory_counters live = { .counters = { .cb = sizeof live }, .private_working_set = SIZE_MAX };
    BOOL extended = GetProcessMemoryInfo(GetCurrentProcess(),(PROCESS_MEMORY_COUNTERS *)&live,sizeof live);
    if (extended && live.private_working_set != SIZE_MAX) {
        assert(live.private_working_set <= live.counters.WorkingSetSize);
        printf("Private working set: %.2f MiB; total working set: %.2f MiB; private commit: %.2f MiB\n",
            live.private_working_set/1048576.0,live.counters.WorkingSetSize/1048576.0,live.counters.PrivateUsage/1048576.0);
    }
    assert(mon_read_memory(GetCurrentProcess(),&p));
    puts("PASS: private working set differs from total residency/commit; zero, unavailable extension and API failure");
}
static void enumeration_tests(void) {
    SYSTEM_PROCESS_INFORMATION record = {0};
    assert(mon_process_snapshot_valid(&record,sizeof record));
    record.NextEntryOffset = 1; assert(!mon_process_snapshot_valid(&record,sizeof record));
    record.NextEntryOffset = 0; record.ImageName.Length = 2; record.ImageName.MaximumLength = 2;
    assert(!mon_process_snapshot_valid(&record,sizeof record));
    assert(!mon_process_snapshot_valid(NULL,0));
    /* Exercise the real fast path and its compatibility fallback against self. */
    mon_collect_process_snapshot(0);
    int fast = -1;
    for (int i = 0; i < mon_count; ++i) if (mon_rows[i].pid == GetCurrentProcessId()) fast = i;
    if (fast >= 0) {
        uint64_t birth = mon_rows[fast].birth;
        mon_count = 0; mon_collect_process_toolhelp(0);
        assert(mon_find_process(GetCurrentProcessId(),birth) >= 0);
    }
    mon_count = 0;
    puts("PASS: bounded process snapshot validation and native/Toolhelp identity agreement");
}
static wchar_t mon_test_expected_path[MAX_PATH];
static int mon_test_reveals;
static HRESULT mon_test_select(PCIDLIST_ABSOLUTE item) {
    wchar_t path[MAX_PATH]; assert(SHGetPathFromIDListW(item, path));
    assert(!wcscmp(path, mon_test_expected_path)); ++mon_test_reveals; return S_OK;
}
static LRESULT CALLBACK test_child_window(HWND window, UINT message, WPARAM w, LPARAM l) {
    if (message == WM_TIMER) { DestroyWindow(window); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, w, l);
}
static int test_child_main(HANDLE ready, bool windowless) {
    HWND window = NULL;
    if (!windowless) {
        WNDCLASSW cls = { .lpfnWndProc = test_child_window, .hInstance = GetModuleHandleW(NULL), .lpszClassName = L"MyGoose action test child" };
        if (!RegisterClassW(&cls)) return 2;
        window = CreateWindowExW(0, cls.lpszClassName, L"MyGoose action test", WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL, cls.hInstance, NULL);
        if (!window || !SetTimer(window, 1, 10000, NULL)) return 2;
    }
    SetEvent(ready); CloseHandle(ready);
    if (windowless) Sleep(10000);
    else { MSG message; while (GetMessageW(&message, NULL, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); } }
    return 0;
}
static void test_child_action(bool force) {
    SECURITY_ATTRIBUTES security = { .nLength = sizeof security, .bInheritHandle = TRUE };
    HANDLE ready = CreateEventW(&security, TRUE, FALSE, NULL); assert(ready);
    wchar_t exe[4096], command[8192]; assert(GetModuleFileNameW(NULL, exe, 4096));
    swprintf(command, 8192, L"\"%ls\" --monitor-child=%llu %ls", exe, (unsigned long long)(uintptr_t)ready, force ? L"--windowless" : L"");
    STARTUPINFOW start = { .cb = sizeof start, .dwFlags = STARTF_USESHOWWINDOW, .wShowWindow = SW_HIDE }; PROCESS_INFORMATION child;
    assert(CreateProcessW(exe, command, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &start, &child)); CloseHandle(child.hThread);
    assert(WaitForSingleObject(ready, 5000) == WAIT_OBJECT_0); CloseHandle(ready);
    FILETIME birth, ended, kernel, user; assert(GetProcessTimes(child.hProcess, &birth, &ended, &kernel, &user));
    uint64_t identity = mon_filetime(birth);
    assert(mon_control_process(child.dwProcessId, identity + 1, force) == MON_ACTION_GONE);
    assert(WaitForSingleObject(child.hProcess, 0) == WAIT_TIMEOUT);
    if (force) assert(mon_control_process(child.dwProcessId, identity, false) == MON_ACTION_NO_WINDOW);
    assert(mon_control_process(child.dwProcessId, identity, force) == MON_ACTION_OK);
    assert(WaitForSingleObject(child.hProcess, 3000) == WAIT_OBJECT_0);
    DWORD code; assert(GetExitCodeProcess(child.hProcess, &code) && code == (force ? 1u : 0u)); CloseHandle(child.hProcess);
}
static void action_tests(void) {
    test_child_action(false); test_child_action(true);
    assert(mon_control_process(4, 1, true) == MON_ACTION_CRITICAL);
    wchar_t temp[MAX_PATH]; assert(GetTempPathW(MAX_PATH, temp));
    swprintf(mon_test_expected_path, MAX_PATH, L"%lsMyGoose %lu %llu \x3042 & space.exe", temp, GetCurrentProcessId(), (unsigned long long)GetTickCount64());
    HANDLE file = CreateFileW(mon_test_expected_path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY, NULL); assert(file != INVALID_HANDLE_VALUE); CloseHandle(file);
    char utf8[4096]; int n = WideCharToMultiByte(CP_UTF8, 0, mon_test_expected_path, -1, utf8, sizeof utf8, NULL, NULL); assert(n > 0);
    assert(mon_reveal_file((mg_string){(const uint8_t *)utf8,n - 1}) == MON_ACTION_OK && mon_test_reveals == 1);
    assert(DeleteFileW(mon_test_expected_path));
    assert(mon_reveal_file(mon_string("relative.exe")) == MON_ACTION_BAD_PATH);
    assert(mon_reveal_file((mg_string){(const uint8_t *)"C:\\a\0b",6}) == MON_ACTION_BAD_PATH);
    assert(mon_test_reveals == 1);
}
#else
static int mon_test_spawn_error, mon_test_reveals;
static int mon_test_spawn(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attrs, char *const argv[], char *const env[]) {
    (void)actions; (void)attrs; (void)env;
#ifdef __APPLE__
    assert(!strcmp(file, "/usr/bin/open") && !strcmp(argv[0], file) && !strcmp(argv[1], "-R") && !argv[3]);
    assert(!strcmp(argv[2], "/tmp/monitor folder ' & \xe3\x81\x82/app.exe"));
#else
    assert(!strcmp(file, "xdg-open") && !strcmp(argv[0], "xdg-open") && !argv[2]);
    assert(!strcmp(argv[1], "/tmp/monitor folder ' & \xe3\x81\x82"));
#endif
    ++mon_test_reveals; *pid = 0; return mon_test_spawn_error;
}
static void test_child_action(bool force) {
    int ready[2]; assert(pipe(ready) == 0); pid_t pid = fork(); assert(pid >= 0);
    if (!pid) {
        close(ready[0]); signal(SIGTERM, force ? SIG_IGN : SIG_DFL);
        char value = 1; if (write(ready[1], &value, 1) != 1) _exit(2); close(ready[1]); sleep(10); _exit(0);
    }
    close(ready[1]); char value; assert(read(ready[0], &value, 1) == 1); close(ready[0]);
#ifdef __APPLE__
    uint64_t birth = mon_macos_birth((uint32_t)pid); assert(birth);
#else
    uint64_t birth = mon_linux_birth((uint32_t)pid); assert(birth);
#endif
    assert(mon_control_process(pid, birth + 1, force) == MON_ACTION_GONE);
    assert(waitpid(pid, NULL, WNOHANG) == 0);
#ifdef __APPLE__
    assert(mon_control_process(pid, birth, force) == MON_ACTION_UNSUPPORTED);
    assert(waitpid(pid, NULL, WNOHANG) == 0);
    /* Only the fixture signals its own child; the sampler declines PID races. */
    assert(kill(pid, force ? SIGKILL : SIGTERM) == 0);
#else
    assert(mon_control_process(pid, birth, force) == MON_ACTION_OK);
#endif
    int status; assert(waitpid(pid, &status, 0) == pid && WIFSIGNALED(status) && WTERMSIG(status) == (force ? SIGKILL : SIGTERM));
}
static void action_tests(void) {
    test_child_action(false); test_child_action(true);
    assert(mon_control_process(1, 1, true) == MON_ACTION_CRITICAL);
    mg_string path = mon_string("/tmp/monitor folder ' & \xe3\x81\x82/app.exe");
    assert(mon_reveal_file(path) == MON_ACTION_OK && mon_test_reveals == 1);
    mon_test_spawn_error = ENOENT; assert(mon_reveal_file(path) == MON_ACTION_UNSUPPORTED);
    assert(mon_reveal_file(mon_string("relative.exe")) == MON_ACTION_BAD_PATH);
    assert(mon_reveal_file((mg_string){(const uint8_t *)"/a\0b",4}) == MON_ACTION_BAD_PATH);
}
#endif

static void core_model_tests(void) {
    assert(mon_core_slots == 0 && !mon_cores_enabled);
    assert(sizeof mon_core_rows <= MON_CORE_CAP * 48); /* bounded current readings, no histories */
    mon_enable_cores(); mon_cores_begin();
    mon_core *a = mon_core_slot(40), *b = mon_core_slot(2); assert(a && b);
    a->seen = b->seen = true; a->value = 20; b->value = 0;
    mon_cores_end();
    assert(mon_core_count() == 2 && mon_core_at(0)->id == 2 && mon_core_value(0) == 0 && mon_core_status() == 1);
    mon_cores_begin(); a->seen = true; a->value = 70; mon_cores_end();
    assert(mon_core_count() == 1 && mon_core_at(0)->id == 40 && mon_core_value(0) == 70);
    mon_cores_begin(); b->seen = true; b->value = 100; mon_cores_end();
    assert(mon_core_count() == 1 && mon_core_at(0)->id == 2 && mon_core_value(0) == 100);
    assert(mon_core_value(-1) == -1 && mon_core_value(128) == -1);
    uint8_t label[48]; assert(mon_core_write_label(0,(mg_bytes){label,sizeof label}) > 0);
#ifdef _WIN32
    uint32_t id = 0;
    assert(mon_core_instance(L"0,17",&id) && id == 17);
    assert(mon_core_instance(L"2,3",&id) && id == 2 * 65536 + 3);
    assert(!mon_core_instance(L"_Total",&id) && !mon_core_instance(L"0,_Total",&id));
    assert(!mon_core_instance(L"1,2,3",&id) && !mon_core_instance(L"-1,2",&id));
    assert(!mon_core_instance(L"65536,2",&id) && !mon_core_instance(L"1,",&id));
    assert(mon_core_pdh_value(PDH_CSTATUS_VALID_DATA,-.5) == 0);
    assert(mon_core_pdh_value(PDH_CSTATUS_NEW_DATA,101) == 100);
    assert(mon_core_pdh_value(PDH_CSTATUS_VALID_DATA,NAN) == -1 && mon_core_pdh_value(PDH_CSTATUS_NO_INSTANCE,0) == -1);
#else
    mon_cores_begin(); mon_core_counters(7,100,10,90); assert(mon_core_slot(7)->value == -1);
    mon_cores_end();
    mon_cores_begin(); mon_core_counters(7,110,15,95); assert(mon_core_slot(7)->value == 75);
    mon_cores_end();
    mon_cores_begin(); mon_core_counters(7,1,1,1); assert(mon_core_slot(7)->value == -1);
    mon_cores_end(); mon_cores_begin(); mon_cores_end();
    mon_cores_begin(); mon_core_counters(7,100,10,90); assert(mon_core_slot(7)->value == -1);
#endif
    mon_cores_close(); mon_enable_cores(); mon_cores_begin();
    for (unsigned i = 0; i < MON_CORE_CAP + 2; ++i) { mon_core *core = mon_core_slot(i); if (core) { core->seen = true; core->value = 0; } }
    mon_cores_end(); assert(mon_core_count() == MON_CORE_CAP && mon_core_omitted() == 2);
    mon_cores_close(); assert(mon_core_count() == 0 && !mon_cores_enabled);
    puts("PASS: per-processor stable IDs, zero/missing readings, hotplug/reset, provider validation and bounded current-value storage");
}
static void model_tests(void) {
    assert(mon_delta(30, 10, 2) == 10);
    assert(mon_delta(10, 30, 2) == 0); /* reset/hotplug cannot wrap */
    assert(mon_delta(30, 10, 0) == 0);
    mon_previous_count = 1;
    mon_previous[0] = (mon_process){ .pid = 42, .birth = 100, .ticks = 1000, .known = true };
    mon_process p = { .pid = 42, .birth = 100, .ticks = 1250, .known = true };
    mon_process_rate(&p, 2, 100); assert(p.cpu == 125 && p.seconds == 12.5);
    p.birth = 101; p.cpu = 0; mon_process_rate(&p, 2, 100); assert(p.cpu == 0);
    p.birth = 100; p.ticks = 999; mon_process_rate(&p, 2, 100); assert(p.cpu == 0);
    mon_previous[0].io_known = true; mon_previous[0].io_read = 200; mon_previous[0].io_write = 100;
    p.io_known = true; p.io_read = 400; p.io_write = 50;
    mon_process_rate(&p, 2, 100); assert(p.read_rate == 100 && p.write_rate == 0);
    p.io_time=10.25; mon_previous[0].io_time=10;
    mon_process_rate(&p,2,100); assert(p.read_rate==800 && p.io_rate_known);
    p.io_time=10; mon_process_rate(&p,2,100); assert(!p.io_rate_known);
    mon_count = 3; ++mon_epoch;
    mon_rows[0] = (mon_process){ .pid = 10, .memory = 50, .known = true, .name = "Alpha.exe" };
    mon_rows[1] = (mon_process){ .pid = 20, .memory = 100, .known = true, .name = "beta.exe" };
    mon_rows[2] = (mon_process){ .pid = 30, .known = false, .name = "Restricted" };
    assert(mon_query(mon_string("ALPHA"), 0, true) == 1 && mon_process_value(0, 0) == 10);
    assert(mon_query(mon_string("20"), 2, false) == 1 && mon_process_value(0, 0) == 20);
    assert(mon_query(mon_string("missing"), 2, false) == 0);
    assert(mon_query(mon_string(""), 2, true) == 3);
    assert(mon_process_value(0, 0) == 10 && mon_process_value(2, 0) == 30);
    mon_query(mon_string(""), 2, false); assert(mon_process_value(0, 0) == 20 && mon_process_value(2, 0) == 30);
    mon_rows[1].memory = MON_MEMORY_UNKNOWN; ++mon_epoch;
    for (int direction = 0; direction < 2; ++direction) {
        mon_query(mon_string(""),2,direction != 0);
        assert(mon_process_value(0,0)==10 && mon_process_value(0,12)==1);
        assert(mon_process_value(1,0)==20 && mon_process_value(1,12)==0 && mon_process_value(1,5)==1);
    }
    mon_rows[1].memory = 100; ++mon_epoch;
    mon_rows[1].birth = 12345;
    assert(mon_find_process(20, 12345) == 1 && mon_find_process(20, 12346) == -1);
    assert(mon_detail_value(1, 2) == 100 && mon_detail_birth(1) == 12345);
    mon_query(mon_string("missing"), 0, true);
    assert(mon_find_process(20, 12345) == 1); /* inspector survives filtering */
    // Alternating rankings must restore their own order, even when the search
    // buffer is reused by the UI. A new sample must invalidate both rankings.
    assert(mon_query(mon_string(""),0,true)==3 && mon_process_value(0,0)==10);
    assert(mon_query(mon_string(""),2,false)==3 && mon_process_value(0,0)==20);
    assert(mon_query(mon_string(""),0,true)==3 && mon_process_value(0,0)==10);
    assert(mon_query(mon_string(""),2,false)==3 && mon_process_value(0,0)==20);
    mon_rows[0].memory=200; ++mon_epoch;
    assert(mon_query(mon_string(""),2,false)==3 && mon_process_value(0,0)==10);
    uint8_t search[]="Alpha"; mg_string query={search,5};
    assert(mon_query(query,0,true)==1 && mon_process_value(0,0)==10);
    memcpy(search,"beta\0",5); query.len=4;
    assert(mon_query(query,0,true)==1 && mon_process_value(0,0)==20);
    memcpy(search,"Alpha",5); query.len=5;
    assert(mon_query(query,0,true)==1 && mon_process_value(0,0)==10);
    assert(mon_query((mg_string){NULL,1},0,true)==0);
    assert(mon_query((mg_string){NULL,-1},0,true)==0);
    // Long searches still use exact bytes, without truncating cache keys.
    uint8_t long_search[4096]; memset(long_search,'a',sizeof long_search);
    assert(mon_query((mg_string){long_search,sizeof long_search},0,true)==0);
    mon_close();
    mon_rows[0].memory=10; /* same epoch, new lifecycle */
    assert(mon_query(mon_string(""),2,false)==3 && mon_process_value(0,0)==20);
    mon_samples = 3; mon_head = 1;
    mon_hist[0][MON_HISTORY - 2] = 10; mon_hist[0][MON_HISTORY - 1] = 20; mon_hist[0][0] = 30;
    assert(mon_history(0, 0, 60, 60) == -1);
    assert(mon_history(0, 57, 60, 60) == 10 && mon_history(0, 59, 60, 60) == 30);
    assert(mon_history(0, 0, 1, 60) == 20); /* average across ring wrap */
    assert(mon_history(-1, 0, 1, 60) == -1);
    mon_hist[7][MON_HISTORY - 2] = -1; mon_hist[7][MON_HISTORY - 1] = 0; mon_hist[7][0] = 30;
    assert(mon_history(7, 0, 1, 60) == 15); /* Missing GPU samples are not idle readings. */
    uint8_t bytes[3];
    assert(mon_copy(mon_string("a\xe3\x81\x82"), (mg_bytes){ bytes, 3 }) == 1); /* no split UTF-8 */
    assert(mon_copy(mon_string("abc"), (mg_bytes){ bytes, 3 }) == 3);
    mon_count=MON_CAP; ++mon_epoch;
    for (int i=0;i<MON_CAP;i++) mon_rows[i]=(mon_process){.pid=(uint32_t)(i+10),.known=true};
    assert(mon_query(mon_string(""),5,true)==MON_CAP && mon_process_value(MON_CAP-1,0)==MON_CAP+9);
    assert(mon_query(mon_string(""),5,false)==MON_CAP && mon_process_value(0,0)==MON_CAP+9);
    assert(mon_query(mon_string(""),5,true)==MON_CAP && mon_process_value(0,0)==10);
    mon_count = mon_previous_count = mon_samples = mon_head = 0;
    memset(mon_rows, 0, sizeof mon_rows); memset(mon_hist, 0, sizeof mon_hist);
}
int main(int argc, char **argv) {
#ifdef _WIN32
    if (argc > 1 && !strncmp(argv[1], "--monitor-child=", 16)) return test_child_main((HANDLE)(uintptr_t)strtoull(argv[1] + 16, NULL, 10), argc > 2);
#else
    (void)argc; (void)argv;
#endif
    action_tests();
#ifdef __APPLE__
    puts("PASS: unsupported process control, stale identity rejection, protected targets and Unicode Finder reveal transport");
#else
    puts("PASS: graceful/forced child-process exit, stale identity rejection, protected targets and Unicode file reveal transport");
#endif
#ifdef _WIN32
    memory_tests();
    enumeration_tests();
    gpu_tests();
#endif
    model_tests();
    core_model_tests(); mon_enable_cores(); mon_set_gpu_active(true);
    assert(mon_sample()); assert(mon_value(MON_MEM_TOTAL) > 0 && mon_value(MON_PROCESSES) > 0);
    assert(mon_value(MON_MEM_USED) >= 0 && mon_value(MON_MEM_USED) <= mon_value(MON_MEM_TOTAL));
    double start = mon_now(); volatile double work = 1;
    while (mon_now() - start < .25) work = sqrt(work + 100);
    assert(mon_sample());
    assert(mon_history_count() == 1 && mon_value(MON_CPU) >= 0 && mon_value(MON_CPU) <= 100);
    if (mon_core_status() >= 0) {
        assert(mon_core_count() > 0 && mon_core_count() <= MON_CORE_CAP);
        for (int i = 0; i < mon_core_count(); ++i) {
            double value = mon_core_value(i); assert(value >= -1 && value <= 100);
        }
    }
    printf("Per-processor counters: %d tracked, status %d\n", mon_core_count(), mon_core_status());
    int gpu_known = 0;
    for (int i = 0; i < mon_count; ++i) if (mon_rows[i].gpu_known) {
        assert(mon_rows[i].gpu >= 0 && mon_rows[i].gpu <= 100); ++gpu_known;
    }
    printf("Per-process GPU: %d available readings, provider state %.0f\n",gpu_known,mon_value(MON_GPU_STATE));
    mg_string pid = mon_format(mon_value(MON_SELF_PID), 0);
    assert(mon_query(pid, 2, false) > 0);
    bool self = false;
    for (int i = 0; i < mon_visible; ++i) if (mon_process_value(i, 0) == mon_value(MON_SELF_PID)) {
        assert(mon_process_value(i, 5) == 1 && mon_process_value(i, 1) > 0);
        assert(mon_process_value(i, 12) ? mon_process_value(i, 2) > 0 : mon_process_value(i, 2) == 0); self = true;
    }
    assert(self);
#ifdef __APPLE__
    /* proc_taskinfo reports Mach ticks, not nanoseconds on Apple Silicon. */
    struct rusage usage; assert(getrusage(RUSAGE_SELF,&usage)==0);
    double native_cpu=usage.ru_utime.tv_sec+usage.ru_stime.tv_sec+
        (usage.ru_utime.tv_usec+usage.ru_stime.tv_usec)/1e6;
    for (int i=0;i<mon_count;i++) if (mon_rows[i].pid==(uint32_t)getpid())
        assert(fabs(mon_rows[i].seconds-native_cpu)<fmax(.03,native_cpu*.1));
#endif
    int index = mon_find_process((int64_t)mon_value(MON_SELF_PID), mon_process_birth(0));
    /* Search can include PIDs that merely contain our PID, so find self explicitly. */
    for (int i = 0; i < mon_count; ++i) if (mon_rows[i].pid == mon_value(MON_SELF_PID)) index = i;
    assert(index >= 0 && mon_detail_value(index, 6) > 0);
    uint8_t path[4096]; assert(mon_write_detail_path(index, (mg_bytes){path, sizeof path}) > 0);
#ifdef __APPLE__
    lazy_io_tests(index);
#endif
    printf("PASS: monitor deltas, PID reuse, filtering, sorting, missing values, history wrap, UTF-8 and live CPU/memory (%d processes, %.1f ms sample)\n", mon_count, mon_value(MON_SAMPLE_MS));
    fflush(stdout); mon_close(); return 0;
}
