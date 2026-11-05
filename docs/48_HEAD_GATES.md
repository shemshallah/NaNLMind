# Learned Boolean heads as relation gates

## 1. HeadGate

`HeadGate` wraps a head that has learned one of the 16 Boolean functions from its
own four input pairs. The same rule is then applied lane-wise to 32-bit relation
masks.

```text
gate = learned head Boolean rule
result = gate(a_mask, b_mask)  // 32 lanes
```

## 2. All 16 functions

`tests/test_relation_boolean_gate.cpp` trains heads 0..15 with the 16 functions
and checks all 16 against `NanWord::eval_bool` for several 32-bit operands.
It then trains head 16 with `A AND NOT B`.

Penguin relation mask:

```text
birds       = 0000_1111   eagle, penguin, sparrow, ostrich
exception   = 0000_1010   penguin, ostrich
can_fly     = birds AND NOT exception
            = 0000_0101   eagle, sparrow
```

The gate also handles a different bit assignment without retraining, and its
mask can be patched and restored.

## 3. Result

```text
16/16 functions learned and checked
penguin mask 0x05 correct
alternate mask 0xD0 correct
self-modify/restore PASS
head array verify PASS
PASS learned Boolean heads as relation gates
```

This is head-level relation evaluation. It does not replace the symbolic logic
baseline; it gives the learned Boolean substrate a real role in the relation
path.

## 4. Next

1. Use gates for exception and kind-chain rules.
2. Train multiple heads per function and select reliable gates through
   overbootstrap.
3. Feed gate outputs into the relation triples.
4. Keep the 100% symbolic baseline as the reference.
