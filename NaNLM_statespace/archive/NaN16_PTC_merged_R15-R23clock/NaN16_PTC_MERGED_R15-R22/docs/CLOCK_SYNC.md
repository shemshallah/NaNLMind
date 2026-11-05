# Logical clock: V4 oscillator + global scratch (experiments/r23_clock/clock_sync.py)

Oscillator: alternate byte-swap S and bit-reverse R on an address: x -> Sx -> RSx -> Rx -> x (4 phases, reversible; verified for all 65,536 addresses).
Orbit sizes: 64,800 addresses have 4 phases, 720 have 2, 16 are static. Of the 256 head anchors (R-fixed): 240 run at half rate, 16 are static.

Simulation: 256 heads, 3% rate drift, 30% of heads dropped for 403 ticks then rejoin with stale phase and epoch; 10 seeds, 1600 ticks.
Phase order = fraction of heads in the plurality phase. Epoch spread = max-min completed-cycle count at the end.

| Mode | order before drop | during drop | late | rejoin recovered | median recovery | epoch spread |
|---|---|---|---|---|---|---|
| free-running | 0.28 | 0.29 | 0.29 | 0/10 | - | 121 |
| local plurality (Hamming-1) | 0.70 | 0.93 | 0.98 | 9/10 | 1 tick | 318 |
| global community scratch (phase + epoch, read p=0.25/tick) | 0.96 | 0.96 | 0.96 | 10/10 | 10.5 ticks | 0.4 |

Reading: local voting reaches good phase agreement but heads disagree on the epoch count (spread 318), so it is not a usable clock. The scratch carries a shared epoch and keeps spread under 1. Scratch phase order is capped near 0.96 by drift between reads.

Earlier static test (no drift, discrete votes): local-only sync worked in 1 of 10 runs (frozen domains); scratch broadcast 10 of 10 in ~7 ticks.

Caveats: logical time only (ordering, epochs, phase); wall-clock needs a real time source in the log. Simulation, not run on real runners; one drift level and one drop pattern. First version of the recovery test was an artifact (drop length a multiple of 4) and was fixed.

Scheduling: bit-reversed slot order keeps any subset of survivors evenly spaced (8 alive of 256: gap 32 = ideal; linear order 249; random ~86).
