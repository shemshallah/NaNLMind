# Explicit small universal table (research status)

## Why this table

The proof path needs an explicit finite transition table, not only a C++
interpreter loop. The smallest 4-symbol table that fits the runtime's 16-state
limit is Neary and Woods's **U6,4** (6 states, 4 symbols, 23 defined
transitions).

Source: T. Neary and D. Woods, "Four Small Universal Turing Machines",
*Fundamenta Informaticae* 91 (2009), Table 12.

## Table

Symbols: `g = 0`, `b = 1`, `c = 2` (blank), `delta = 3`.
States: `u1 = 0` through `u6 = 5`. Entries are write, move, next state.

| state | g | b | c | delta |
|---|---|---|---|---|
| u1 | b,L,u1 | g,L,u1 | delta,L,u1 | c,R,u2 |
| u2 | g,R,u1 | g,R,u2 | g,R,u5 | c,R,u2 |
| u3 | b,L,u3 | b,L,u5 | delta,L,u3 | delta,L,u5 |
| u4 | b,R,u2 | g,R,u4 | c,R,u5 | c,R,u4 |
| u5 | b,L,u6 | g,R,u6 | b,L,u3 | delta,R,u5 |
| u6 | b,L,u4 | g,R,u5 | halt | g,R,u1 |

`(u6,c)` is the undefined halting pair. The C++ test loads the 23 defined
transitions into the table-driven runtime and compares every step against an
independent map-based reference.

## What this closes

- The runtime can execute an explicit, literature-backed finite universal table
  within its state/symbol limits.
- The table is stored as ordinary chart transition entries, not a host
  task-specific branch.
- The companion Minsky 23-state/8-symbol table now executes a normally encoded
  binary machine; see doc 71.

## What it does not close

- The U6,4 table expects the Neary-Woods bi-tag tape encoding. We have not
  implemented the TM -> clockwise TM -> bi-tag -> tape compiler or decoder.
- Therefore this is not yet a self-encoded universal description (O3).
- It is not yet a trace-equivalence proof for the interpreter (O5).
