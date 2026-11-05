# UTM proof harness

## 1. Versioned description grammar

`TmDescription` format:

```text
NLMTM001
u16 version, u16 states, u16 alphabet, u16 count
count * 6-byte transitions
SHA-256 checksum
```

Validation rejects bad states/symbols/moves and checksum corruption.

## 2. Randomized cross-check

The test also exhausts every 1-state, 2-symbol deterministic table (144
machines), and runs 20 randomly generated TMs (4 states, 3 symbols). Each is run
through:

1. table-driven `TuringMachine`, and
2. fixed-step `UniversalTuringMachine` reading the encoded description.

After every step, compare:

```text
state, head, halted, tape slice
```

All agree. This is the strongest current evidence that the interpreter really
reads the machine description.

## 3. Ledger-linked checkpoint

After binary increment:

```text
tape -> SHA-256
ledger.commit(...)
ledger.verify()
restore tape into a fresh UTM
tape(0,4) == 1100
```

So tape state has a checkpoint digest and survives a restored machine instance.

## 4. What is still missing for a formal UTM proof

- a self-encoded universal machine description (a UTM description that runs
  another description);
- a complete formal grammar covering every TM, not just valid tables;
- tape pages registered in the atlas allocator and ledger, not only hashed;
- a finite formal transition table/ROM version of the interpreter;
- a proof that the interpreter's search/update loop is itself a fixed finite
  machine.

## 5. Test

```text
PASS UTM proof harness: grammar, random cross-check, ledger checkpoint
```

The word “proof” here means a checked proof harness, not the final theorem.
