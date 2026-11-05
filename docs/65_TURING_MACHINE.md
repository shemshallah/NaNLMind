# Actual Turing machine runtime

## 1. Structure

`TuringMachine` is a general TM runtime:

- transition table in chart address registers;
- state and head in address registers;
- tape symbols in allocated 8 MiB `Universe` pages;
- one fixed `step()`.

This is not a host function that just computes an answer. The table is read from
chart cells each step.

## 2. Machine

Binary increment:

```text
state 0, read 1 -> write 0, move left, stay state 0
state 0, read 0 -> write 1, stay, HALT
state 0, read blank -> write 1, stay, HALT
```

`1011` -> `1100`.

`111` propagates the carry into a new blank cell at position -1:

```text
tape(-1..2) = 1000
```

## 3. Test

```text
PASS general Turing machine: binary increment
```

Tape pages are allocated on demand; state/head/table are in chart registers.

## 4. Honest boundary

This is an actual **TM runtime**, not a UTM proof:

- no universal transition table yet;
- no TM -> 2CM compiler yet;
- tape growth is page-allocated but not yet tied to atlas allocator/ledger;
- no claim that this runtime is UTM-equivalent.

## 5. Next

1. Link `TuringTape` pages to the atlas allocator and ledger.
2. Add a universal transition table in ROM cells.
3. Prove the same machine runs multiple encoded TMs.
4. Then (and only then) claim UTM.
