// Local measurement helper; deliberately not linked into ClickBoom.
#include <errno.h>
#include <libproc.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <time.h>

static int parse_int(const char *text, long min, long max, int *value) {
    char *end;
    errno = 0;
    long n = strtol(text, &end, 10);
    if (errno || end == text || *end || n < min || n > max) return 0;
    *value = (int)n;
    return 1;
}

static int read_usage(int pid, struct rusage_info_v4 *usage) {
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)usage) == 0) return 1;
    perror("proc_pid_rusage");
    return 0;
}

static int wait_seconds(int seconds) {
    struct timespec remaining = { .tv_sec = seconds };
    while (nanosleep(&remaining, &remaining) != 0) {
        if (errno == EINTR) continue;
        perror("nanosleep");
        return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    int pid, warmup = 10, duration = 60;
    if (argc < 2 || argc > 4 || !parse_int(argv[1], 1, INT_MAX, &pid) ||
        (argc > 2 && !parse_int(argv[2], 0, 3600, &warmup)) ||
        (argc > 3 && !parse_int(argv[3], 1, 3600, &duration))) {
        fprintf(stderr, "Usage: %s PID [warmup_seconds=10] [sample_seconds=60]\n", argv[0]);
        return EXIT_FAILURE;
    }

    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) {
        fputs("Failed to get the Mach timebase.\n", stderr);
        return EXIT_FAILURE;
    }

    struct rusage_info_v4 first, baseline, current;
    if (!read_usage(pid, &first)) return EXIT_FAILURE;
    fprintf(stderr, "Warm-up: %d s; measurement: %d s. Keep the workload active until completion.\n",
            warmup, duration);
    if (!wait_seconds(warmup) || !read_usage(pid, &baseline)) return EXIT_FAILURE;
    if (baseline.ri_proc_start_abstime != first.ri_proc_start_abstime) {
        fputs("Target changed during warm-up.\n", stderr);
        return EXIT_FAILURE;
    }

    struct timespec start, end;
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
        perror("clock_gettime");
        return EXIT_FAILURE;
    }
    uint64_t peak = baseline.ri_phys_footprint;
    for (int i = 0; i < duration; ++i) {
        if (!wait_seconds(1) || !read_usage(pid, &current)) return EXIT_FAILURE;
        if (current.ri_proc_start_abstime != baseline.ri_proc_start_abstime) {
            fputs("Target changed during measurement.\n", stderr);
            return EXIT_FAILURE;
        }
        if (current.ri_phys_footprint > peak) peak = current.ri_phys_footprint;
    }
    if (clock_gettime(CLOCK_MONOTONIC, &end) != 0) {
        perror("clock_gettime");
        return EXIT_FAILURE;
    }
    double elapsed = (double)(end.tv_sec - start.tv_sec) + (double)(end.tv_nsec - start.tv_nsec) / 1e9;
    // proc_pid_rusage CPU times are Mach ticks, not nanoseconds.
    double cpu_ticks = (double)(current.ri_user_time - baseline.ri_user_time) +
                       (double)(current.ri_system_time - baseline.ri_system_time);
    double cpu_seconds = cpu_ticks * timebase.numer / timebase.denom / 1e9;
    double mib = 1024.0 * 1024.0;
    puts("seconds,cpu_pct_one_core,peak_sampled_phys_mib,pkg_idle_wakeups,interrupt_wakeups");
    printf("%.3f,%.4f,%.3f,%llu,%llu\n", elapsed, 100.0 * cpu_seconds / elapsed, (double)peak / mib,
           (unsigned long long)(current.ri_pkg_idle_wkups - baseline.ri_pkg_idle_wkups),
           (unsigned long long)(current.ri_interrupt_wkups - baseline.ri_interrupt_wkups));
    return EXIT_SUCCESS;
}
