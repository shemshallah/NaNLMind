#include "temporal_nan.h"

#include <stdio.h>
#include <string.h>

/*
 * The prototype treats the temporal address space explicitly:
 *
 *   low addresses  --------------------------> high addresses
 *       LE / PAST                              BE / FUTURE
 *
 * Address 0 is the oldest/LE boundary.
 * Address TN_MEMORY_CELLS-1 is the newest/BE boundary.
 *
 * The program is allocated at the BE boundary. A temporal result travels
 * toward LE and causes a rewrite of the future program. This is an explicit
 * machine rule, not ordinary CPU endianness.
 */

uint64_t tn_qnan_pos_bits(void) {
    /* Quiet NaN: sign=0, exponent=all ones, quiet bit set. */
    return UINT64_C(0x7ff8000000000000);
}

uint64_t tn_snan_neg_bits(void) {
    /* Negative signaling NaN with a nonzero payload. */
    return UINT64_C(0xfff0000000000001);
}

const char *tn_state_name(tn_program_state state) {
    return state == TN_PROGRAM_HALT ? "HALT" : "LOOP";
}

const char *tn_signal_name(tn_signal_kind signal) {
    return signal == TN_SIGNAL_QNAN_POS ? "+qNaN" : "-sNaN";
}

const char *tn_direction_name(tn_direction direction) {
    return direction == TN_DIR_BE ? "BE/FUTURE" : "LE/PAST";
}

const char *tn_event_name(tn_event_kind kind) {
    switch (kind) {
        case TN_EVENT_ALLOCATE: return "ALLOCATE";
        case TN_EVENT_EXECUTE: return "EXECUTE";
        case TN_EVENT_SIGNAL: return "SIGNAL";
        case TN_EVENT_REWRITE: return "REWRITE";
        case TN_EVENT_CONTRADICTION: return "CONTRADICTION";
        case TN_EVENT_CYCLE: return "CYCLE";
        default: return "UNKNOWN";
    }
}

static void log_event(tn_temporal_machine *m,
                      tn_event_kind kind,
                      int address,
                      tn_direction direction,
                      tn_program_state state,
                      tn_signal_kind signal,
                      int target_address) {
    if (m->event_count >= TN_EVENT_MAX) return;
    tn_event *e = &m->events[m->event_count++];
    e->tick = m->tick;
    e->address = address;
    e->direction = direction;
    e->kind = kind;
    e->state = state;
    e->signal = signal;
    e->target_address = target_address;
}

void tn_init(tn_temporal_machine *m) {
    memset(m, 0, sizeof(*m));

    m->future_address = TN_MEMORY_CELLS - 1;
    m->past_address = 0;
    m->execution_direction = TN_DIR_BE;

    /* Start with the grandfather-paradox seed: future HALT. */
    m->future_program = TN_PROGRAM_HALT;
    m->past_rewrite = TN_PROGRAM_HALT;

    for (int i = 0; i < TN_MEMORY_CELLS; ++i) {
        m->program_at[i] = TN_PROGRAM_HALT;
    }

    m->program_at[m->future_address] = m->future_program;

    m->memory[m->future_address] = UINT64_C(0x48414c54); /* "HALT" tag */
    m->history[m->history_count++] = m->future_program;

    log_event(m, TN_EVENT_ALLOCATE, m->future_address, TN_DIR_BE,
              m->future_program, TN_SIGNAL_QNAN_POS, m->past_address);
}

static void execute_future(tn_temporal_machine *m) {
    m->future_program = m->program_at[m->future_address];

    log_event(m, TN_EVENT_EXECUTE, m->future_address, TN_DIR_BE,
              m->future_program, TN_SIGNAL_QNAN_POS, m->past_address);

    if (m->future_program == TN_PROGRAM_HALT) {
        m->signal.kind = TN_SIGNAL_QNAN_POS;
        m->signal.bits = tn_qnan_pos_bits();
    } else {
        m->signal.kind = TN_SIGNAL_SNAN_NEG;
        m->signal.bits = tn_snan_neg_bits();
    }

    log_event(m, TN_EVENT_SIGNAL, m->future_address, TN_DIR_BE,
              m->future_program, m->signal.kind, m->past_address);
}

static void apply_past_feedback(tn_temporal_machine *m) {
    /*
     * Grandfather feedback rule:
     *   +qNaN -> past changes the future program to LOOP.
     *   -sNaN -> past changes the future program to HALT.
     *
     * The rewrite is intentionally directed from LE/PAST to the BE/FUTURE
     * allocation cell.
     */
    if (m->signal.kind == TN_SIGNAL_QNAN_POS) {
        m->past_rewrite = TN_PROGRAM_LOOP;
    } else {
        m->past_rewrite = TN_PROGRAM_HALT;
    }

    m->contradiction = (m->past_rewrite != m->future_program);

    m->program_at[m->future_address] = m->past_rewrite;

    log_event(m, TN_EVENT_REWRITE, m->past_address, TN_DIR_LE,
              m->past_rewrite, m->signal.kind, m->future_address);

    if (m->contradiction) {
        log_event(m, TN_EVENT_CONTRADICTION, m->past_address, TN_DIR_LE,
                  m->future_program, m->signal.kind, m->future_address);
    }
}

void tn_step(tn_temporal_machine *m) {
    execute_future(m);
    apply_past_feedback(m);

    if (m->history_count < TN_HISTORY_MAX) {
        m->history[m->history_count++] = m->past_rewrite;
    }

    m->tick++;
}

void tn_run(tn_temporal_machine *m, size_t max_ticks) {
    for (size_t i = 0; i < max_ticks; ++i) {
        tn_step(m);

        size_t start = 0, length = 0;
        if (tn_find_cycle(m, &start, &length)) {
            if (m->event_count < TN_EVENT_MAX) {
                log_event(m, TN_EVENT_CYCLE, m->future_address, TN_DIR_BE,
                          m->future_program, m->signal.kind, m->past_address);
            }
            m->cycle_start = start;
            m->cycle_length = length;
            return;
        }
    }
}

int tn_find_cycle(const tn_temporal_machine *m,
                  size_t *cycle_start,
                  size_t *cycle_length) {
    if (m->history_count < 3) return 0;

    /*
     * Search for a repeated state. The smallest suffix period is preferred.
     * This is deliberately generic so the machine can later support
     * longer temporal cycles than the current period-2 paradox.
     */
    size_t n = m->history_count;

    for (size_t len = 1; len <= n / 2; ++len) {
        size_t a = n - len;
        size_t b = a - len;
        int equal = 1;

        for (size_t i = 0; i < len; ++i) {
            if (m->history[b + i] != m->history[a + i]) {
                equal = 0;
                break;
            }
        }

        if (equal) {
            if (cycle_start) *cycle_start = b;
            if (cycle_length) *cycle_length = len;
            return 1;
        }
    }

    return 0;
}

void tn_dump(const tn_temporal_machine *m) {
    printf("temporal memory: cells=%d\n", TN_MEMORY_CELLS);
    printf("  LE/PAST boundary  : %d\n", m->past_address);
    printf("  BE/FUTURE boundary: %d\n", m->future_address);
    printf("  cursor direction  : %s\n",
           tn_direction_name(m->execution_direction));
    printf("  future program    : %s\n", tn_state_name(m->future_program));
    printf("  past rewrite      : %s\n", tn_state_name(m->past_rewrite));
    printf("  signal            : %s (0x%016llx)\n",
           tn_signal_name(m->signal.kind),
           (unsigned long long)m->signal.bits);
    printf("  contradiction     : %s\n", m->contradiction ? "YES" : "NO");
    printf("  tick              : %llu\n", (unsigned long long)m->tick);
}

void tn_dump_events(const tn_temporal_machine *m) {
    printf("\ncausal event log (%zu events)\n", m->event_count);
    for (size_t i = 0; i < m->event_count; ++i) {
        const tn_event *e = &m->events[i];
        printf("  t=%03llu addr=%02d dir=%-9s %-14s state=%-4s sig=%-5s -> %02d\n",
               (unsigned long long)e->tick,
               e->address,
               tn_direction_name(e->direction),
               tn_event_name(e->kind),
               tn_state_name(e->state),
               tn_signal_name(e->signal),
               e->target_address);
    }
}
