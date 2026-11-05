# Deterministic layers: coupling, closure, NTT

## 1. Reversible coupling

```text
forward:  (x1, x2) -> (x1, x2 XOR F(x1)) mod 2^16
inverse:  (y1, y2) -> (y1, y2 XOR F(y1))
```

`F` is a fixed integer permutation. Seven layers round-trip exactly. No
activations need to be stored for the inverse; this fits forward/rollback
frames.

Test: `PASS reversible integer coupling`.

## 2. Boolean semiring closure

A 256×256 chart edge matrix supports:

```text
closure  reflexive-transitive reachability
A        forward inheritance
Aᵀ       backward inheritance
```

Implementation: bitset rows, Warshall closure, Boolean multiply. A 256-node
chain reaches from 0 to 255 and from 42 to 255, but not backward.

Test: `PASS Boolean semiring closure`.

This is the first matrix-algebra layer that matches the K₂₅₆ graph view.

## 3. Exact NTT over F257

`257` is Fermat; its multiplicative group has order 256, so a 256-point NTT is
exact in integers modulo 257.

- forward + inverse round-trips 256 values;
- NTT cyclic convolution matches the naive scan exactly;
- no floats.

Test: `PASS exact 256-point NTT over F257`.

## 4. What this gives the stack

- reversible coupling for deep train/rollback;
- semiring closure for inheritance and frame sync;
- NTT for correlation/sketches over heads;
- the four-NaN transform chain and Boolean spectrum on top.

## 5. Falsifiable next

1. NTT correlation vs naive on a real sequence.
2. Closure-based inheritance vs the 20k symbolic split.
3. Reversible coupling vs stored activations on one task.
4. Kill 30% of slots and recover.
5. Hypervector 20k split.
