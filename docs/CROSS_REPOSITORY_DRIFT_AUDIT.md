# Whole NaN ecosystem source-drift audit

This is a **source-contract audit, not a claim that every repository runs one
shared checkpoint**. The source scanner inventories all 24 NaN-named
repositories from the linked GitHub organization. It records each checked-out
repository head SHA, every tracked file SHA-256 and size, shared relative source
paths (identical/divergent), plus hard-gated byte-parity and worker invariants.

The audit is repeatable: \`integration/cross_repo_drift.py\` is exercised by
\`.github/workflows/nan-cross-repo-contracts.yml\` on relevant PRs, pushes,
daily GitHub Actions and manual dispatch. The workflow checks out each
populated repository's **current** \`main\` (shallow), never writes to them,
and uploads \`nan-cross-repo-audit.json\`.

## Repository roles and what was actually compared

| Family | Repositories | Interface or audit target |
| --- | --- | --- |
| Native NaN16 | NaN0S | C VM / NaN16 guest / bank and N16T source |
| Android | NaNLMind_android, nan0s-android | Android/NaN0S C parity, guest protocol and APK; \`nan0s-android\` is currently an empty repository |
| Core state and distribution | NaNLMind, NaNLM, nan0 | Core 8 MiB chart and training merge; NaNLM has a **separate experimental VM/model**, not an asserted drop-in model |
| Router and cognition | NaNROUTER, NaNLMind_HERMES, NaNLMind_CLOCKED, nanrunner-hermes | Layer graph, signed lease/native head fence, plugin chart, evidence gateway and helper client |
| RAM/VRAM tiers | nanlm-ram, nanlm-vram | Currently mostly tier documentation; do not mistake an address/tier definition for running allocated memory |
| Head compute | nanlm-cpu-1 .. nanlm-cpu-6 | Six distinct slot identities with matching workflow logic |
| Router standby compute | nanrouter-runner-0 .. nanrouter-runner-5 | One identical implementation, different slot metadata; NOT six independently trained minds |

### Strict source contracts enforced

- NaN0S → Android: byte-identical \`aarch64/android/core/nan16.c\`,
  \`nan16.h\`, \`nan16_int.h\`, and \`src/nannet/n16t_android_guest.nas\`.
  The Android \`n16t_android_abi.nas\` is **not** forcibly equated to NaN0S:
  it contains server-side protocol work that is independently tested.
- NaNLMind → HERMES: identical \`nan16de.py\` wire codec bytes, notwithstanding
  distinct package paths.
- All six \`nanrouter-runner\` repositories: identical tracked source,
  workflows, tests, runtime and deployment files; \`README.md\` and literal
  \`slot\` are the only permitted differences. Every slot must match 0..5.
- All six \`nanlm-cpu\` repositories: identical workflow code after exact
  normalization of just four *required* per-worker fields: workflow input
  slot 1..6, \`NANNET_BOOTSTRAP_SLOT\` 0..5, assigned \`BSRn_PORTAL_API\`
  environment alias, and \`NANNET_PORTAL_API\` mapping. Any other change to
  a workflow or tracked-file inventory fails CI. The CPU workers and router
  standbys are **different mechanisms** and should not be merged into one.

The tool fails closed on missing clones, missing contract files, changed
digests, worker identity changes, and unexpected per-worker code differences.
Every shared relative source pathname (including legitimate differences
between unrelated components) is separately inventoried in the JSON report,
without pretending equal filenames imply compatible semantics.

### Outstanding semantic reconciliation

1. **Head reservation and identity:** NaNLMind's root README describes all
   256 fixed palindrome heads as available and none reserved. NaNROUTER's
   README reserves six internal BSR control head indices (0, 4, 5, 6, 7, 8),
   while recent router/HERMES mirror tables treat head 0 as network/boot and
   expose 255 writable learning heads. Hardware point identities (\`HW5:0\`
   and \`BS0:0\`) are a separate namespace from local palindrome heads.
   These statements need an explicit versioned **runtime** head ACL contract
   before silently treating 256, 255 or 250 as the same learnable capacity.
2. **Native learning provenance:** digest-matched MC0DB graph pages are
   projections, not remotely authenticated signatures or MTH verdicts.
   The newer Router/HERMES 3-repo native head tests check persistent-chart
   rebase and guest receipts. A general graph-admission → native MTH verdict
   → authorized graph promotion protocol still requires independent gates.
3. **Release pinning:** Android uses a pinned NaN0S boot-image baseline for
   reproducible APK packaging, but NaN0S's newer C core is now synchronized
   in Android. The boot image, native runtime C and guest binary versions
   must always be reported as *separate source identities*.
4. **Reproducibility and deployment:** GitHub Actions checks out main heads
   individually, not one atomic cross-repository Git transaction. The
   reported per-repo head SHAs allow later reconstruction. Runtime services,
   registered network leases and external credentials are not measured here.

## Run without installing third-party dependencies

\`\`\`bash
python -m unittest discover -s tests -p 'test_cross_repo_drift.py' -v
# The GitHub Actions workflow clones the 23 nonempty public repositories.
python integration/cross_repo_drift.py \
  --root /path/to/repository-checkouts \
  --output nan-cross-repo-audit.json
\`\`\`

**Interpretation:** PASS means the declared source-byte and worker invariants
hold at the recorded Git heads. It does **not** certify the trained model,
authenticity of cross-machine identities, availability of remote services,
quantum effects or successful native mathematical execution.
