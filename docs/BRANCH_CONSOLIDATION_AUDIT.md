# NaNLMind branch consolidation audit

Audited 2026-11-10 against repository `shemshallah/NaNLMind`, default branch `main`.

- **Canonical integration branch**: `main`. The unified 48M language math, 128 MiB tensor controller, and frozen decoder candidate tests are committed directly to `main` without starting a new model or experimental branch.
- **Pre-existing Git refs**: 45 branches total (44 non-main), even though only one PR was open. A large branch count is not evidence that 44 language models or states exist.
- **Fully behind main (11, zero unique commits; safe *candidates* for deleting the branch pointer)**:
  - `docs/runner-ring-authority-20261108`
  - `feat/atomic-runner-ring-authority-20261108`
  - `feat/nannet-koyeb-router-cutover`
  - `feat/single-service-portal-ring-ingress-20261108`
  - `feature/retire-koyeb-config-examples-20261108`
  - `gpt/global-persistence-ntf`
  - `graph-spectral-foundation`
  - `math-catalog-unification`
  - `nan-rawroute-four-tier-addressing`
  - `nannet-canonical-route-hardening`
  - `rss-sparse-capability-contract`

Those 11 were checked via GitHub compare (base main, head branch) and each reported ahead_by=0. Check comparison again immediately before deleting any ref in case another actor pushes new commits. Deletion of a branch REF is distinct from deletion of its content in main. Do not use force-push of main to tidy branches.

- **Diverged (33)**: retain their unique commits until the changed files have been reviewed for overlap, outdated design or incompatibility. Some are hundreds of main commits behind. Cherry-pick a sound component onto `main` only after testing; do not merge old branch tips wholesale. Some examples include `clocked-universe-nannet` (117 ahead, 609 behind), `nannet-universal-intake` (111 ahead, 609 behind), `resolution-aware-conversation-learning` (40 ahead, 510 behind), and `feat/v2-geometric-trail-field-credit` (2 ahead, 119 behind). Ahead counts are *not* necessarily 1:1 with unique files or desirable features.

## One remaining open PR

[PR #43](https://github.com/shemshallah/NaNLMind/pull/43) is a draft seven-method native training proposal on `feature/mth-seven-credit-nanlm-train-20261109`; 17 commits ahead of and 97 commits behind main at audit time. It modifies the guest driver, raw-field API, Makefile, tests and adds CLI. Its own PR description says fixtures are not evidence of improved language quality. It has deliberately **not** been merged into the newer mainline without compatibility verification.

## Retiring refs without losing code

Use GitHub's Branches page, or the guarded script `scripts/retire_fully_merged_branches.sh` with `--execute`. The script re-fetches main/remote branch heads and checks ancestry before deleting each ref. By default, it is a dry run. GitHub-only admin mutations may require appropriately permissioned credentials. This source repository does NOT contain the original 48M checkpoint; the archive and its two SHA-256 anchors are recorded in `docs/48M_UNIFIED_HEAD_TRIHEAD_TENSOR_META.md`.

### Interpretation of completion

- Done: single canonical active integration target `main`, no new feature branch generated, eight tested/CI-wired integration changes committed to main, and an explicit remaining-branches audit.
- Not done: deleting GitHub's 44 old branch refs, landing carefully reviewed unique code from all 33 diverged refs, end-to-end native candidate meta learning / new held-out language improvement. Do not label those finished.
