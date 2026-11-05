# 256-head Boolean curriculum

## 1. What is trained

Each of the 256 self-modifying heads is assigned one target function from the
16-function Boolean space:

```text
target = head_index mod 16
```

Training covers all four input pairs 100 times. The head selects the winning
function from its scratchpad score table and writes the 16-bit operator mask.

## 2. Bit manipulation

Each head evaluates five 32-bit operand pairs from its local scratchpad and is
compared lane-for-lane with `NanWord::eval_bool(target, a, b)`:

```text
0x00000000 / 0xFFFFFFFF
0xFFFFFFFF / 0x00000000
0xAAAAAAAA / 0x55555555
0x55555555 / 0xAAAAAAAA
0x12345678 / 0x9ABCDEF0
```

## 3. Self-modification

Each head performs an individual XOR patch on its operator mask, checks the
mask changed correctly, then restores it. The selected rule returns to the
learned function.

## 4. Result

```text
heads with learned rule:       256/256
bit vectors checked:           1,280/1,280
self-modification restores:    256/256
head array verify:             PASS
```

Test:

```bash
./build/test_boolean_curriculum
```

This is head-level Boolean learning and bit manipulation. It does not claim that
the 256 heads have learned the penguin logic or the massive triple baseline; it
gives those layers a correct Boolean substrate.

## 5. Next

1. Use learned heads as logic gates in relation-rule evaluation.
2. Feed relation/exception traces through head masks.
3. Train multiple heads per function and use overbootstrap to select reliable
   gates.
4. Keep the symbolic 100% baseline separate from learned gate behavior.
