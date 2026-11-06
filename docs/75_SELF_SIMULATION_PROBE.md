# Self-simulation probe

## Setup

The probe compiles the 23-state / 8-symbol Minsky table into the 508-state
binary machine, encodes that binary machine as a Minsky universal-machine
description, and runs the chart Minsky table over it.

```text
binary states       508
binary transitions  1014
state bits p        9
description         22,308 symbols
total tape          22,385 symbols
initial head        72
```

Run:

```sh
make self-sim-probe
# or
./build/self_sim_probe 100000000
```

## Observed result

After 100,000,000 chart Minsky steps:

```text
ran=100000000 halted=0 state=2 head=11062 pages=6
```

The probe is running, but the Minsky scanner has not yet completed a full
description pass. The bottleneck is structural: the universal Minsky table
scans the encoded program for every simulated binary microstep, and the
compiled Minsky program is 22 KB.

## Honest conclusion

This is a reproducible **partial self-simulation run**, not a completed
self-simulation. The compiler, tape encoder, and chart execution path all work;
the full run needs either:

1. a much larger CI budget, or
2. a smaller direct table-interpreter encoding with a compact self-delimiting
   description.

Do not claim a completed self-simulation from this probe.
