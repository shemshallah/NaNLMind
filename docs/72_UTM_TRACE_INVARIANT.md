# UTM trace invariant

## 1. Relation

For a table-driven machine `M` and the encoded universal interpreter, define the
configuration relation:

```text
R( (q, h, T), (q_e, h_e, D, W) )
```

where:

- `q`, `h`, `T` are the reference TM state, head, and tape;
- `q_e`, `h_e` are the interpreter's simulated control state and working head;
- `D` is the encoded transition table on the description tape;
- `W` is the working tape.

The relation requires:

```text
q_e = q
h_e = h
W[p] = T[p] for every checked position p
D[k] = decode(table)[k]
```

## 2. One-step obligation

If `R` holds and `M` has a transition `(q, T[h]) -> (q', T', m)`, then the
interpreter must produce:

```text
q_e' = q'
h_e' = h + m
W' = W with W[h] replaced and otherwise unchanged
```

If no transition exists, both machines must halt.

## 3. What is checked now

- Every one-state, two-symbol table (144 machines), 12 steps each.
- 20 randomized 4-state, 3-symbol machines, 30 steps each.
- The explicit U6,4 table against an independent map reference.
- The complete Minsky 23-state, 8-symbol table against a Python trace.
- The encoded Minsky universal description against the table-driven reference
  for 100 steps.
- A normally encoded binary machine through the Minsky table to its halt.

## 4. What is not a proof

The checks are bounded traces. The following remain:

- prove the invariant inductively for all reachable configurations;
- prove the interpreter's control is a finite transition table;
- prove the encoder/decoder round-trip for every TM, not just tested tables;
- obtain a self-encoded description of the 23x8 table itself.

The correct status remains **checked universal table and encoded description**,
not **proved UTM equivalence**.
