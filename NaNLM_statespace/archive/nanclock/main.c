#include "temporal_nan.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(const char *argv0) {
    printf("usage: %s [ticks] [--events]\n", argv0);
    printf("  ticks     number of temporal transitions (default: 8)\n");
    printf("  --events  print the causal event log\n");
}

int main(int argc, char **argv) {
    size_t ticks = 8;
    int events = 0;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--events") == 0) {
            events = 1;
        } else {
            char *end = NULL;
            unsigned long v = strtoul(argv[i], &end, 10);
            if (!end || *end != '\0' || v == 0) {
                print_usage(argv[0]);
                return 2;
            }
            ticks = (size_t)v;
        }
    }

    tn_temporal_machine m;
    tn_init(&m);

    printf("NaN temporal memory prototype v2\n");
    printf("BE/FUTURE = high address; LE/PAST = low address\n");
    printf("qNaN/sNaN are carried as exact 64-bit bit patterns\n\n");

    for (size_t i = 0; i < ticks; ++i) {
        tn_step(&m);

        printf("tick %llu: future=%s -> %s -> past rewrites future=%s",
               (unsigned long long)(m.tick - 1),
               tn_state_name(m.future_program),
               tn_signal_name(m.signal.kind),
               tn_state_name(m.past_rewrite));

        if (m.contradiction) {
            printf(" [CONTRADICTION]");
        } else {
            printf(" [CONSISTENT]");
        }
        printf("\n");
    }

    size_t start = 0, length = 0;
    if (tn_find_cycle(&m, &start, &length)) {
        printf("\ncycle detected: start=%zu length=%zu\n", start, length);
        printf("temporal orbit: ");
        for (size_t i = start; i < m.history_count; ++i) {
            printf("%s", tn_state_name(m.history[i]));
            if (i + 1 < m.history_count) printf(" -> ");
        }
        printf("\n");
    } else {
        printf("\nno repeated temporal state within the captured history\n");
    }

    tn_dump(&m);

    if (events) {
        tn_dump_events(&m);
    }

    return 0;
}
