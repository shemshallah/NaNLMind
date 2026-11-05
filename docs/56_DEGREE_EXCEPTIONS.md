# Nested exceptions need polynomial degree

## 1. Target

For nesting depth `d`:

```text
flies = bird AND NOT exception_1 AND ... AND exception_d
```

Over F₂ this is a degree `d + 1` monomial. The test builds the full truth table
over 8 variables and computes its exact ANF. A degree-limited model zeroes all
ANF coefficients above degree `D`, then reconstructs.

## 2. Result

| depth | target degree | degree 0 | 1 | 2 | 3 | 4 | 5 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2 | .750 | .750 | **1** | 1 | 1 | 1 |
| 2 | 3 | .875 | .625 | .875 | **1** | 1 | 1 |
| 3 | 4 | .938 | .563 | .813 | .938 | **1** | 1 |
| 4 | 5 | .969 | .531 | .781 | .844 | .969 | **1** |

Accuracy becomes exact exactly at `D = depth + 1`; every lower degree is
strictly worse.

## 3. Why this matters

- A byte-count model has no predicate variables, so it cannot express
  “exception beats inheritance” in this way.
- The degree result gives the macrocluster/hyperedge layer a concrete job:
  hold the higher-degree terms.
- The test is falsifiable and deterministic; no floats, no training noise.

## 4. Test

```sh
./build/test_degree_exceptions
```

## 5. Next

1. Learn sparse degree terms from samples rather than full truth tables.
2. Test degree 2/3/4 terms on the 20k corpus.
3. Map degree-2 terms to one exception level, degree-3 to nested clauses.
4. Keep the symbolic baseline as grader.
