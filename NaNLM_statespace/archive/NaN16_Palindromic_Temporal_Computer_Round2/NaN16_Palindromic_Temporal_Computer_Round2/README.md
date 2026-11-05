# NaN16 Palindromic Temporal Computer — Round 2

This archive contains two design brainstorms and a small C++20 reference prototype.

## Contents

- `BRAINSTORM_1.md` — PTME, temporal RAM, endian transforms, and research directions.
- `BRAINSTORM_2.md` — pair-cell state machine, capacity accounting, paging, and parallelism.
- `src/address_orbits.cpp` — exhaustive address-transform and orbit enumerator.
- `tests/test_reference.cpp` — deterministic assertions for address algebra and temporal-pair behavior.
- `Makefile` — build/test targets.
- `design/FORMAT.md` — proposed page and pair-cell record layout.
- `TEST_RESULTS.txt` — captured test output.

## Build and run

Requires a C++20 compiler (clang++ or g++).

```sh
make test
```

Or:

```sh
clang++ -std=c++20 -O2 -Wall -Wextra -Wpedantic src/address_orbits.cpp tests/test_reference.cpp -o test_reference
./test_reference
```

## Scope and limitations

This is a host-side reference model. It is not a native NaN16 compiler, hardware implementation, virtual-memory manager, cryptographic primitive, or performance proof. It exhaustively checks the 16-bit address mathematics and exercises a tiny event-logged shared-state pair.

The reference uses bit reversal for the 32,640 mirror-pair count. Byte-swap has the same number of fixed points and pairs, but the two transformations are distinct. Their combined action is counted as 16,576 group orbits, with orbit sizes 1, 2, or 4.

No claim of 2× speedup or 2× memory is made. Shared-state pairs use one payload; dual-state pairs would require two payloads. Parallel throughput must be measured on a real scheduler and workload.
