# How big is this, really? How big could it be?

## What is real *now* (16-bit instance)

| Quantity | Value | Meaning |
|----------|------:|---------|
| Raw addresses | 65,536 | Full 16-bit domain |
| Canonical cells | 32,896 | Unit of topology state |
| Mirror pairs | 32,640 | Sites of two-sided structure |
| Fixed points | 256 | Self-mirroring special sites |
| Config space (shared 1-bit) | ~10^9,903 | Global binary configurations |
| Config space (dual 1-bit/side) | ~10^19,728 | If each pair has independent S+,S- |
| Config space (dual 8-bit/side) | ~10^157,826 | Modest payload per side |

Atoms in the observable universe ≈ 10^80. Even the **shared 1-bit** configuration space of this 16-bit machine is astronomically larger. Address count is small; **joint state space** is not.

## What Round 7 established about pairs

- **Mirror independence (Exp 1):** S+ and S- can be transformed independently with zero isolation failures (single cell + 1024×50 bulk).
- **Complementary transitions (Exp 2):** Forward XOR + reverse recovery restores the original on 32/32 and 1024/1024 trials.
- This is still **API-level dual state** on the host model — not yet proof that *local neighborhood rules alone* orchestrate complementary work across pairs. It is necessary groundwork: the pair can hold two sided state without clobbering.

## How big it *could* be

### A. Wider addresses (same construction)
For even width n under bit-reversal:
- fixed points = 2^(n/2)
- pairs = (2^n − 2^(n/2))/2
- cells = 2^(n−1) + 2^(n/2−1)

| n | cells | rough 1-bit config space |
|--:|------:|--------------------------|
| 8 | 136 | 10^41 |
| 16 | 32,896 | 10^9,903 |
| 24 | ~8.4e6 | 10^2.5e6 |
| 32 | ~2.15e9 | 10^6.5e8 |

A 32-bit instance is no longer a laptop toy; it is a large distributed state machine. Still finite.

### B. Dual-state without wider addresses
Giving each pair (S+, S−) **doubles payload bits** at fixed address width. That is the cheapest expansion: same topology, richer cells.

### C. Hierarchy / paging
Keep 16-bit *local* topology pages, stitch many pages with portals (fixed-point banks as inter-page gates). Configuration space multiplies; local rules stay small.

### D. What “big” does *not* mean
- Not 32,640 CPUs.
- Not proven advantage over a plain graph CA of similar size.
- Not unbounded RAM in one fixed instance (finite ⇒ eventual cycles if deterministic and closed).

## Bottom line

**How big is it really?**  
A finite, exact, 32,896-cell symmetric state machine whose **configuration space** is already beyond physical enumeration, with working dual-state isolation and signal-carried arithmetic on the 16-bit instance.

**How big could it be?**  
Polynomial in 2^n cells as width grows; exponential configuration space; dual-state and paging multiply capacity without changing the core idea. The interesting limit is not address count — it is whether local rules + mirror structure can organize that space into *composed, programmable computation* without the host smuggling the algorithm.
