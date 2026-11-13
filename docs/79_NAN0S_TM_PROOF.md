# NaN0S Turing-machine proof bridge

This is the runnable bridge between the host Turing/UTM proof construction and
the canonical NaN0S guest. It does not replace the honest mechanization boundary
in `docs/69_UTM_PROOF_OBLIGATIONS.md`.

## 1. What runs

Host side (`NaNLMind`):

```text
build/test_turing_machine       table-driven TM + tape persistence
build/test_universal_tm         fixed-step encoded-description interpreter
build/test_utm_proof             grammar, randomized cross-check, ledger checkpoint
build/test_small_utm             explicit U6,4 table
build/test_minsky_utm            Minsky 23x8 table trace
build/test_minsky_encoded        normally encoded binary machine
build/test_utm_universal_desc    encoded Minsky universal description
build/test_binary_tm_compiler    23x8 -> 508-state binary compiler
build/test_binary_utm            compact binary runtime
build/test_binary_utm_self       compiled Minsky own-tape trace
build/test_tape_checkpoint       page checkpoint in the sharded journal
```

Guest side (`~/nan0s`, canonical portable core):

```text
src/tests/tm_test.nas       one table-driven NaN16 TM step
src/tests/tm_n16i_test.nas  the same guest inside n16i (NaN16 in NaN16)
tools/tm_gate.sh            native == interpreted, exact tape checks
```

The guest TM runs three cases with the same `step()` code:

```text
binary increment  1011 -> 1100
unary increment   111  -> 1111
carry             111  -> 1000 (new cell at -1)
```

The gate requires:

```text
TM GATE PASS (native == n16i; ...)
TM BINARY 1100 PASS
TM UNARY 1111 PASS
TM CARRY 1000 PASS
TM ALL PASS
```

`n16i` is the NaN16 interpreter written in NaN16. Running the same TM guest
natively and under `n16i` makes the "one system, canonical VM" link explicit:
the interpreter and the native core produce byte-identical serial output.

## 2. Run the whole checked proof

From the NaNLMind repository:

```sh
make utm-proof
```

That target builds the host proof tests, runs them, invokes the canonical NaN0S
`tools/tm_gate.sh`, and writes:

```text
state/benchmarks/utm_proof.json
```

The report has separate `host` and `guest` sections and a combined
`PASS`/`FAIL`. It is ignored by git as a runtime artifact.

Without a NaN0S checkout, use the host-only path:

```sh
python3 tools/run_utm_proof.py --skip-build
```

The guest gate is skipped unless `--require-guest` is supplied. `make
utm-proof` always requires the guest gate.

## 3. What is proved, and what is not

Proved/checked here:

- the host table-driven TM, encoded-description UTM, Minsky table, binary
  compiler, compact binary runtime, and tape checkpoint tests pass;
- one canonical NaN16 table-driven TM runs natively and under the NaN16
  self-interpreter with identical output and expected tapes;
- the guest TM test is part of the AArch64 differential gate (`qgate_a64.sh`).

Not proved here:

- a mechanized inductive equivalence proof for every TM/input;
- a completed recursive self-encoding of the 23x8 table into itself;
- a formal theorem that `n16i` is a UTM. The honest claim remains a checked
  universal construction plus a checked interpreter gate.
