# Native NaNLMind seven-credit training entry

Binary: `build/nanlm-train` (C++20 command/ABI adapter; mathematical
kernels execute inside the canonical NaN0S NaN16 VM).

Run:

```sh
make -j2 build/nanlm-train build/test_raw_field
./build/nanlm-train tests/fixtures/mth-seven-positive.n16mth --out build/mth-trained.weights
./build/nanlm-train tests/fixtures/mth-seven-rejected.n16mth --out build/mth-resumed.weights --resume build/mth-trained.weights
make mth-seven-check
```

The eight-dimensional causal trunk and QKV/readout resident in the guest are
initialized to a deterministic identity-based test configuration. The
training controller does not substitute host mathematical algorithms for
CFT, TRAIL, HOLO, RING, LEAF, TCA, FLUX, weighted credit combining, or the
native gate. The host writes typed registers and reads the outputs.

## Source input `N16MTH/1`

Blank lines and `#` comments are allowed. All numbers are decimal or
`0x` hexadecimal; negatives are signed. The first non-comment line must
be `N16MTH/1`. Subsequent records:

```text
phase HEAD_0_TO_254 TURN_0_TO_65535
step CONTEXT_8_BYTES_HEX TARGET_HEAD WRONG_HEAD BASE_LR_Q16 THRESHOLD_Q16 CFT5 TRAIL11 HOLO3 RING_SHIFT LEAF3 TCA3 FLUX4 COEFF7
```

Each `step` contains exactly **42 arguments after the keyword**.
`CFT5`, `TRAIL11`, etc. denote the explicitly ordered arguments of the
corresponding source kernel, not literal strings. The fixture files
contain concrete records.

| Channel | Inputs | Extracted signed credit |
|---|---|---|
| CFT | edge AB, BC, CA, local error, rate | returned triangle circulation residual |
| TRAIL | reward, inverse next, forward current, forward previous, inverse current, two traces, two local gradients, gamma, lambda | returned signed two-rail TD credit |
| HOLO | three 16-bit-turn phases | returned `1 - cos(sum phases)` defect |
| RING | live 255-head turn phase array and shift | returned average cosine |
| LEAF | full unsigned 32-bit row bits, leaf mask, signed Q16 counter | support × counter |
| TCA | current head log-probability and two peer log-probabilities | leave-one-out advantage |
| FLUX | two node potentials, link weight, source | flow × divergence |

Coefficient array order is **CFT, TRAIL, HOLO, RING, LEAF, TCA, FLUX**.
Each coefficient is Q16.16, applied through original
`mth_credit_combine.nas`. The chosen signed combined credit passes
`mth_credit_gate.nas`; acceptance controls the raw trunk and QKV
update. Head 255 is reserved. The raw guest retains one model state
through multiple `step` records.

A `phase` record changes the current ring phase array for subsequent
steps. This is **input data**, not a hidden training signal synthesized by
the host.

## Output

The `--out` file contains `N16MTHWEIGHTS/1` and the final learned
trunk matrices `WQ`, `WK`, `WV`, `WOUT`, `W1`, `W2`
as hex floating-point text for reproducible inspection. The CLI also
emits one `NANLM_MTH7_STEP` row per step with each **actual raw guest**
credit, combined credit, gate acceptance and `bptt_attempted=0`.
The final `NANLM_MTH7_TRAIN` receipt includes rows and accepted count.

`--resume PREVIOUS.weights` restores all six exact trunk/QKV matrices into
the same logical VM before any native training step. The zero-credit control
proves a rejected update leaves the persisted weights byte-identical.
The CFT/TRAIL/combined gate's accepted Q16.16 learning rate is converted
into the required IEEE float32 bits **inside the NaN16 guest**, using native
`CVTIF`/`FDIV` before updating trunk parameters.

The output is a **native MTH trunk weight artifact**, NOT a serialized
8 MiB global universe or a fully resumed checkpoint. It does not
alter the existing NaNLM v1 `build/nanlm_train` (toy HDC generator).

## Verification and limits

The branch's `mth-seven-credit-verify.yml` workflow compiles the
native driver and CLI, invokes full raw-field C++/guest regressions,
assembles the canonical guest fixture suite, and checks a positive
`N16MTH/1` learning example against a rejected-credit control.
No user-provided corpus or false semantic signal is manufactured.

This proves an **explicit seven-method train-step interface**, not
the ability to derive all seven causal quantities from arbitrary
Gutenberg text. The next production feature-extractor needs native
Q16 values from the actual mirror pairs, temporal links, head phases,
hypermatrix leaf masks, peer predictions, and noninvented error
signals; then a transactional 2/3 triad and 43/85 field vote with a
held-out objective and rollback. In the absence of a real per-sample
signal, do not silently set coefficients or fabricate feature values.

An improvement in head-vector byte CE or a passing deterministic
fixture is not evidence of generalized semantic understanding.
