# Round 18T Summary: Transposition Correspondence, Resonance, Learning

## 1. Structural result (verified, `make test18t`, 12/12 pass, real Topology cells)
- With addr(a,b) = (a<<8) | rev8(b): reverse16(addr(a,b)) == addr(b,a). Bit reversal IS transposition on the 256x256 head grid.
- 256 fixed points = diagonal. 32,640 mirror pairs = unordered head pairs. W[a][b] and W[b][a] are S+ / S- of one shared dual cell.
- Dense signed, sparse, and antisymmetric matrices round-trip exactly; writing one direction leaves the other untouched.

## 2. Resonance (verified)
Power iteration x <- Wx on matrices read back from cells:
| W | result |
|---|---|
| symmetric | dominant real mode: x(t+2) = +x(t) |
| antisymmetric | dominant imaginary pair, quarter-turn rotation: x(t+2) = -x(t), <x_t,x_t+1> = 0 |
| 50/50 mix | generic rotation angle |
The symmetric half gives stable modes; the antisymmetric half gives rotation.

## 3. Sequence memory (verified)
Hebbian cyclic sequences, N=256: asymmetric storage replays up to 20 patterns exactly (overlap >0.99 to 48). Symmetric storage cannot replay order (~50% overlap).

## 4. Learning (experiments/r18t_rnn/, numpy BPTT, gradient-checked, single seed)
Model: h' = tanh(W h + U[x] + b), logits = V h + c, 256 hidden units (the 256 heads).
W is either full, symmetric-only, or antisymmetric-only (the two halves of the transposition structure).
Batch 16 x 32 bytes, Adam 3e-3, 3200 iterations = 1.64M bytes seen. Held-out bits/byte (uniform = 8):

| Corpus | bigram | full W | symmetric W | antisymmetric W |
|---|---|---|---|---|
| A: docs, 27.8 KB | 3.97 | 3.64 best @800, 4.08 @3200 (overfits) | 3.49 @3200 | 3.51 @3200 |
| B: C++ source, 174 KB | 3.54 | 2.20 | 2.69 | 2.44 |

Learning speed: the full model passes the bigram baseline at about 51K bytes seen on B (3.45 @ iter 100) and about 100K bytes on A. About 1 minute of single-core CPU per 3200 iterations.

## 5. What this does and does not show
- Asymmetric coupling matters: on B, antisymmetric beats symmetric by 0.25 bits and full beats both. A symmetric-only W is the weakest option once data is sufficient.
- On the small corpus the constrained variants beat full W only because full W overfits (train 1.44 vs held-out 4.08). That is regularisation, not a structural advantage.
- A full RNN whose W is stored in the topology is mathematically an ordinary RNN. Nothing here shows the topology improves learning over a plain dense matrix; it is the addressing and storage scheme, with the forward/backward bigram read for free from transposed cells.
- Not a competitive language model: 2.2 bits/byte on repetitive code, ~3.5 on prose. Single seed, so A-corpus gaps of ~0.05 are within noise. "best" values on A are checkpoint-selected on held-out data and slightly optimistic; fixed-iteration columns are not.
- Not done: trained W stored/reloaded through the C++ cells (storage is verified separately above), multiple seeds, multi-layer or larger-vocab models.

## 6. Next
Multi-seed runs, a plain-dense-RNN control with matched parameter count (to test any topology advantage honestly), W round-trip of a trained net through cells, then widen beyond 256 units (multi-layer, or the matrix as routing over RepoRAM).
