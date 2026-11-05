# Boolean spectrum and four-NaN transforms

## 1. Four NaN types select transform phases

```text
+qNaN  QuietPositive   phase 0  I   quiet future
+sNaN  SignalPositive  phase 1  B   signaling future
-qNaN  QuietNegative   phase 2  BR  quiet past
-sNaN  SignalNegative  phase 3  R   signaling past
```

The transform group is Klein-four: every element is its own inverse. The first
inverse implementation used `4 - phase`; that was wrong. The fixed inverse
applies the same phase again.

Test: `PASS four-NaN transform chain` (65,536 addresses × 4 types).

## 2. Boolean ANF

For truth-table bits `f00,f01,f10,f11`:

```text
c0  = f00
ca  = f00 XOR f10
cb  = f00 XOR f01
cab = f00 XOR f10 XOR f01 XOR f11
```

`truth_from_anf` is exact for all 16 functions. `cab = 1` is the nonlinear
indicator.

## 3. Walsh spectrum

Four integer coefficients are the signed parity correlations. The largest
coefficient identifies the parity-like behavior. Coefficients are exact
integers; no floats.

## 4. Symmetry classes

The 16 functions collapse under input swap/negation and output negation:

```text
0 constant
1 literal
2 XOR/XNOR
3 AND/OR family
```

Histogram over the 256-head curriculum:

```text
constant  32
literal   64
xor       32
and      128
```

The test verifies class invariance over all swap/negation/output variants.

## 5. Transpose split

Any 256×256 chart matrix splits:

```text
S = M + Mᵀ   symmetric     "goes with" / similarity
A = M - Mᵀ   antisymmetric "before/after" / direction
M = (S + A) / 2
```

`S` is symmetric, `A` is antisymmetric, transpose is an involution, and the
split test passes. This is the matrix form of the `s+`/`s-` rails.

## 6. Test

```sh
./build/test_transform_chain
./build/test_boolean_spectrum
```

Both pass.
