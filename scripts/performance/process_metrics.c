#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <time.h>

static int parse_pid(const char *value) {
    char *end = NULL;
    errno = 0;
    long parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || parsed <= 0 || parsed > INT32_MAX) {
        return -1;
    }
    return (int)parsed;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: process_metrics PID\n");
        return 64;
    }

    int pid = parse_pid(argv[1]);
    if (pid < 0) {
        fprintf(stderr, "invalid pid: %s\n", argv[1]);
        return 64;
    }

    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
        perror("proc_pid_rusage");
        return 1;
    }

    struct proc_taskinfo task = {0};
    int task_bytes = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task));
    if (task_bytes != (int)sizeof(task)) {
        if (task_bytes < 0) {
            perror("proc_pidinfo");
        } else {
            fprintf(stderr, "proc_pidinfo returned %d bytes, expected %zu\n", task_bytes, sizeof(task));
        }
        return 1;
    }

    struct timespec now = {0};
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &now) != 0) {
        perror("clock_gettime");
        return 1;
    }
    uint64_t timestamp_ns = (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;

    printf(
        "%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64
        ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%d,%d,%d,%d,%" PRIu64 ",%" PRIu64 "\n",
        timestamp_ns,
        usage.ri_user_time,
        usage.ri_system_time,
        usage.ri_pkg_idle_wkups,
        usage.ri_interrupt_wkups,
        usage.ri_resident_size,
        usage.ri_phys_footprint,
        usage.ri_lifetime_max_phys_footprint,
        task.pti_csw,
        task.pti_threadnum,
        task.pti_syscalls_mach,
        task.pti_syscalls_unix,
        usage.ri_instructions,
        usage.ri_cycles
    );
    return 0;
}
