# Raw NaN16 adaptive field kernels

Status: **native NaN16 source and fixtures**. This is the raw-NaN path for
per-head self-modification, triad voting, field voting, and phase coherence.
The kernels are assembled with the canonical NaN0S `nmk.awk` and executed by
`nan_cli`; the host Python script only invokes those tools and records output.

## Why this exists

The C++ chart code owns storage, serialization, ledger commits, and transport.
It must not substitute host Boolean, field, trig, or remap arithmetic for a
native kernel. The raw sources in `mth/nan16/` are the authority for the
adaptive-field mathematics:

| kernel | role |
|---|---|
| `mth_bool_dynamic.nas` | dynamic 16-function Boolean evaluation and masks |
| `mth_triad_vote.nas` | one-head proposal + independent member votes |
| `mth_field_vote.nas` | 85-triad field majority |
| `mth_q16_sin_cos.nas` | integer CORDIC sine/cosine in 16-bit turn units |
| `mth_field_coherence.nas` | 255 pairwise phase terms averaged to Q16.16 |
| `mth_triad_score.nas` | correct-member + majority objective for one probe |
| `mth_remap_decision.nas` | fixed A1/B0 trial swap with exact rollback |
| `mth_remap_general.nas` | arbitrary triad-slot trial, exact table restore |
| `mth/drivers/field_driver.nas` | guest command dispatcher for proposal, field vote, coherence and remap |
| `include/nanlm/raw_field.hpp` | host orchestration: writes command words, runs the VM, reads results |

## Per-head proposal ABI

`mth_triad_vote.nas`:

```text
r1 current proposer mask (16 bits)
r2 XOR patch proposed by that head
r3,r4,r5 member masks 0,1,2
r6,r7 operand A,B
r8 target bit
-> r1 vote mask, r2 accepted, r3 candidate mask, r4 candidate rule
```

Each member evaluates its own Boolean rule on the same operands. The candidate
must predict the target; the proposal applies only when at least two members
approve. The caller applies the XOR patch to the proposer only. This is
different from the older broadcast operation that copied one patch to all three
heads.

## Field vote ABI

`mth_field_vote.nas` reads a pointer to 85 32-bit word entries. The low three
bits of each entry are the triad vote mask. It returns the accepted count and
whether at least 43 triads accept. The trig kernel and field-coherence kernel
are separate native primitives; a caller can combine the field count with the
Q16.16 coherence value.

## Learnable credit, not host gradients

A production caller stores accepted/rejected proposal counts and bounded
integer credit fields in chart state. Those are **integer credit fields**, not
floating-point gradients and not BPTT. The raw kernels decide proposals and
votes; the chart/ledger remains the persistence boundary.

The C++ chart fields (`triad_members`, `triad_votes`, head/triad credit) are
storage and serialization. `RawFieldVM` now bridges a proposal to the guest:
it marshals masks and operands, runs `field_driver.nas` on the pinned NaN0S C
core, and applies only the proposer's accepted mask. `RawFieldVM::field_vote`
and `coherence` also write the chart's field count and stored Q16.16 value.
The canonical NaN0S C core and assembler are vendored under
`third_party/nan0s/` with `SOURCE.json`; `third_party` is host/VM transport,
not a second math implementation.

This is still a bounded bridge: the full training loop, general remap
persistence and the host-side scheduler are separate gates. The C++ training
path does not silently invoke the guest yet; `field-selftest` and
`test_raw_field` exercise the bridge explicitly.

## Run the fixtures

```sh
make nan16-test
./build/nanlm-universal field-selftest
# or:
python3 tools/run_nan16_fixtures.py --nan0s-root ~/nan0s
```

`NAN16_REQUIRE=1` makes a missing NaN0S toolchain a hard failure instead of a
skip. The default fixtures cover:

- a true candidate approved by two members and a false candidate rejected;
- one-member agreement rejected;
- exactly 43 accepted triads pass the field majority, 42 do not;
- Q16.16 sin/cos at 0, 90, 180, and 270 degrees;
- field coherence with 85 coherent triads and one perturbed triad;
- a fixed and a general triad remap accepted only when they improve the
  majority objective, with exact rollback and chart mapping commit;
- the field-command driver and the `RawFieldVM` chart bridge;
- `field-selftest` and `test_raw_field` on the vendored canonical VM.

## Remap decision

`mth_remap_decision.nas` is the first raw remap gate: it scores two triads
before and after a fixed A1/B0 mask swap, accepts only when the combined
objective improves, and restores the table exactly on rejection.
`mth_remap_general.nas` generalizes this to any two triad slots.
`RawFieldVM::remap_chart` commits the corresponding chart mapping swap only
after the raw guest returns an improvement; the mapping is serialized with
the Universe. What remains open is the autonomous scheduler that chooses
which triads to trial and when.

## Non-claims

- No host Boolean/trig/field arithmetic is used by these fixtures.
- No BPTT, float tensor, PyTorch, or v1 overlay is imported.
- No natural-language fluency, live Koyeb/NANNET, or geometric advantage is
  claimed.
- The fixtures are native execution evidence, not a claim that the full
  decoder or a source-disjoint benchmark is complete.
