# Teacher, gate, grader

## 1. The three-stage check

```text
Hopfield          recalls the relation-qualified candidate
HeadGate          applies the exception rule (A AND NOT B)
TripleStore / WordMemory / hypervector
                  grades the result
```

`tests/test_teacher_gate.cpp` covers the cassowary case:

```text
cassowary isa bird
bird can fly
cassowary cannot fly
-> can cassowary fly? no
```

## 2. What is exercised

- Hopfield relation recall: `cassowary_cannot -> fly`;
- learned Boolean head `A AND NOT B` over the bird/exception mask;
- symbolic triple store grader;
- `WordMemory` exception/ability checks;
- XOR hypervector direct recall for `cassowary cannot -> fly`.

## 3. Result

```text
PASS teacher, Boolean gate, and triple-store grader
```

This is the first explicit three-way integration. It is still a small,
hand-built relation case, not the 20k corpus. The components now meet.

## 4. Next

1. Run the same three-stage check on the 20k generated split.
2. Use the triple store as a teacher labeler for the hypervector layer.
3. Let overbootstrap choose between Hopfield candidates and hypervector
   candidates.
4. Add degree-2/3 terms for nested exceptions.
