# UTM implementation status

## Closed in the implementation

### Fixed universal table

- Minsky 23-state, 8-symbol table, 184 complete transitions.
- Loaded as ordinary chart transition entries.
- Matches the Python reference trace for 100 published steps.
- Executes a normally encoded binary machine to its halt transition.

### Encoded universal description

- The same Minsky table is encoded as a `TmDescription`.
- The encoded description is loaded into the fixed-step
  `UniversalTuringMachine`.
- It executes an encoded binary machine on its working tape and matches the
  table-driven reference for 100 steps.

### Ledger page index

- Tape page hashes and signed page keys are committed as journal records.
- `TapePageIndex` reconstructs the page map from the journal and verifies every
  key/hash against the checkpoint.
- Atlas-attached tapes allocate new pages through `Atlas`.

### Trace harness

- Exhaustive one-state/two-symbol tables.
- Random four-state/three-symbol tables.
- Explicit U6,4 reference check.
- Minsky Python reference check.
- Encoded-description reference check.

## One remaining limitation

The equivalence checks are bounded traces and randomized/exhaustive families.
They are not a mechanized inductive proof for every machine/input, and the
23x8 table is not encoded as an input to itself. The implementation is a genuine
fixed universal machine with an encoded universal description, but the theorem
statement remains a checked harness rather than a proof-assistant artifact.

That limitation is documented in `docs/72_UTM_TRACE_INVARIANT.md`; it is not
hidden behind a UTM claim.
