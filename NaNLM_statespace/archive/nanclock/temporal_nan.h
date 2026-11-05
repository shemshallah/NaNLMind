#ifndef TEMPORAL_NAN_H
#define TEMPORAL_NAN_H

#include <stdint.h>
#include <stddef.h>

#define TN_MEMORY_CELLS 64
#define TN_HISTORY_MAX  256
#define TN_EVENT_MAX    512

typedef enum {
    TN_PROGRAM_HALT = 0,
    TN_PROGRAM_LOOP = 1
} tn_program_state;

typedef enum {
    TN_DIR_LE = -1,
    TN_DIR_BE = 1
} tn_direction;

typedef enum {
    TN_SIGNAL_QNAN_POS = 0,
    TN_SIGNAL_SNAN_NEG = 1
} tn_signal_kind;

typedef enum {
    TN_EVENT_ALLOCATE = 0,
    TN_EVENT_EXECUTE = 1,
    TN_EVENT_SIGNAL = 2,
    TN_EVENT_REWRITE = 3,
    TN_EVENT_CONTRADICTION = 4,
    TN_EVENT_CYCLE = 5
} tn_event_kind;

typedef struct {
    uint64_t bits;
    tn_signal_kind kind;
} tn_temporal_signal;

typedef struct {
    uint64_t tick;
    int address;
    tn_direction direction;
    tn_event_kind kind;
    tn_program_state state;
    tn_signal_kind signal;
    int target_address;
} tn_event;

typedef struct {
    tn_program_state future_program;
    tn_program_state past_rewrite;
    int future_address;
    int past_address;
    tn_direction execution_direction;

    tn_temporal_signal signal;
    int contradiction;

    uint64_t tick;
    uint64_t cycle_start;
    uint64_t cycle_length;

    uint64_t memory[TN_MEMORY_CELLS];
    tn_program_state program_at[TN_MEMORY_CELLS];

    tn_event events[TN_EVENT_MAX];
    size_t event_count;

    tn_program_state history[TN_HISTORY_MAX];
    size_t history_count;
} tn_temporal_machine;

/* Exact IEEE-754 encodings carried as integer bits.
   They are NEVER used as floating-point arithmetic values. */
uint64_t tn_qnan_pos_bits(void);
uint64_t tn_snan_neg_bits(void);

const char *tn_state_name(tn_program_state state);
const char *tn_signal_name(tn_signal_kind signal);
const char *tn_direction_name(tn_direction direction);
const char *tn_event_name(tn_event_kind kind);

void tn_init(tn_temporal_machine *m);
void tn_step(tn_temporal_machine *m);
void tn_run(tn_temporal_machine *m, size_t max_ticks);

int tn_find_cycle(const tn_temporal_machine *m,
                  size_t *cycle_start,
                  size_t *cycle_length);

void tn_dump(const tn_temporal_machine *m);
void tn_dump_events(const tn_temporal_machine *m);

#endif
