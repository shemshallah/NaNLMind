#!/bin/sh
set -eu

make clean
make
output="$(./temporal_nan 6 --events)"

printf '%s\n' "$output"

printf '%s\n' "$output" | grep -q "tick 0: future=HALT -> +qNaN -> past rewrites future=LOOP"
printf '%s\n' "$output" | grep -q "tick 1: future=LOOP -> -sNaN -> past rewrites future=HALT"
printf '%s\n' "$output" | grep -q "cycle detected: start=3 length=2"
printf '%s\n' "$output" | grep -q "CONTRADICTION"
printf '%s\n' "$output" | grep -q "ALLOCATE"
printf '%s\n' "$output" | grep -q "REWRITE"

echo "PASS: temporal memory + NaN feedback + period-2 cycle"
