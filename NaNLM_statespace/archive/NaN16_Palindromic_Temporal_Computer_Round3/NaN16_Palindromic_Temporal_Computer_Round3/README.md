# NaN16 Palindromic Temporal Computer — Round 3

**Snapshot of the Round 3 architecture** (topology cells, no-PC computation).

Every address pair is a computational cell. The 16-bit address space is a finite
computational topology. Local transition rules evolve state; there is no
conventional instruction-fetch-and-execute loop.

## Build

```sh
make test
```

## Demonstrated in Round 3

- Rule 90 → Sierpinski (local law, global structure)
- Signal propagation and decay
- Spatial arithmetic geometry (adder)
- Locally reversible XOR
- Majority consensus
- 256 fixed-point (palindromic) addresses as a subsystem

Round 4 (separate archive) extends this with Rule 110, arithmetic families,
dual fields, and a reversibility audit.
