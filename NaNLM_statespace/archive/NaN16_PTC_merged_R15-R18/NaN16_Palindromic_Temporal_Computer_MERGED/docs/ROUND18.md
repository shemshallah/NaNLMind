# Round 18 — NaN16 Transposition Correspondence

**Theorem.** With addr(a,b) = (a<<8) | rev8(b), reverse16(addr(a,b)) = addr(b,a).
Bit reversal is matrix transposition on the 256x256 head grid.
256 fixed points = diagonal; 32,640 mirror pairs = unordered head pairs; W[a][b] is S+ (or S-) of the shared dual cell.

**Verified in tests/test_round18.cpp (run `make test18`), using real Topology cells:**
- exhaustive over all 65,536 addresses; one physical cell per {W[a][b], W[b][a]}
- dense signed, sparse, and antisymmetric matrices round-trip exactly; one-direction writes are isolated
- x<-Wx: symmetric => real dominant mode (x_{t+2}=+x_t); antisymmetric => quarter-turn rotation (x_{t+2}=-x_t); mixed => generic angle
- Hebbian cyclic sequence memory: asymmetric storage replays P<=20 patterns exactly at N=256 (overlap >0.99 to P=48); symmetric storage cannot replay order

**Not yet shown:** learning from data, context beyond one step, any advantage over a plain dense matrix.
