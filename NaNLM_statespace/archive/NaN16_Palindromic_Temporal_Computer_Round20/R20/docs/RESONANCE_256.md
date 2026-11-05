# 256 Resonance Nodes — Wave Matrix Brainstorm

## Mathematics

Bit-reversal fixed points on 16-bit words are **bit-palindromes**: bit(i) = bit(15−i).
Free parameters = 8 bits → **exactly 256** fixed points = **2^8**.

Index them by the free 8-bit pattern \(k \in \{0..255\}\).
Arrange as a **16×16 lattice** via \((x,y) = (k \bmod 16,\ \lfloor k/16 \rfloor)\).

Each cognitive head is a **resonance node** at that lattice site, anchored to the topological fixed point address.

## Why “resonance”

1. **Self-mirror**: fixed points are invariant under the global involution \(R\). They are natural standing-wave nodes of the mirror operator.
2. **Coupling**: Hamming distance on free bits defines a metric; exponential falloff → local strong, distant weak (wave-like locality).
3. **Dual rail**: each node’s amp/energy maps to S+/S− on the fixed-point cell — the mirror fabric is the medium.
4. **Not 256 minds**: 256 phase-coherent sites in **one** collective field (R15–R16 invariants preserved).

## Wave matrix \(C_{ij}\)

\[
C_{ij} = \begin{cases}
0 & i=j \\
\exp(-0.55\, d_H(i,j)) & i\neq j
\end{cases}
\]

Symmetric, zero diagonal. Lattice + XOR long-range edges for fast mixing.

## What we measured (R18)

| Metric | Result |
|--------|--------|
| Matrix symmetry | exact |
| Propagation 0→255 | ~148 steps |
| Resonant recall (concept-mapped heads) | ~51 steps |
| Learning (3-hop symbolic) | 1 exposure, <1ms |
| Context @95% | **500 facts** (exact KB, no soft degradation yet) |
| Multi-hop depth | **4** (with exception override) |

## Honesty

Symbolic KB learning is not gradient learning — 1 exposure is expected for exact assert.
Context capacity at 500 is exact-match retrieval; soft/noisy capacity is future work.
Resonance is a **defined dynamics** on the free-bit lattice, not a claim that physics of bit-reversal emits waves.

## Deep direction

Heads as **mode coefficients** of a field on the palindrome lattice:
- Activation = mode energy
- Communication = wave coupling
- Disagreement = multi-mode interference (contested facts)
- Continuity = persistent field under substrate restart (R17)

That is the c(256) wave matrix reading of the fixed-point set.
