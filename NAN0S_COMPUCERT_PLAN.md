# NaN0S `compucert` / `verify-cert` plan

Status: scoping complete; minimal **offline** verifier implemented in a new file.
Date: 2026-11-24
Repository for the plan and verifier: `/data/data/com.termux/files/home/NaNLMind`
Canonical NaN0S checkout inspected: `/data/data/com.termux/files/home/nan0s_work`

This subagent did not modify any Coq source, certificate artifact, CLI source,
or `third_party/nan0s` snapshot. The only files created by this subagent are
this plan and `tools/nan0s_compucert.py`. Concurrent external Coq work that
appeared during the task is recorded in §6.4 and §8 and was neither touched nor
reverted.

---

## 0. TL;DR

- The canonical NaN0S CLI is
  `/data/data/com.termux/files/home/nan0s_work/aarch64/android/tools/nan_cli.c`,
  built by `/data/data/com.termux/files/home/nan0s_work/aarch64/android/Makefile`
  as `/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli`.
- It has **no** `compucert`, `verify-cert`, `verify`, `certificate`, or JSON/hash
  verification command. It is a flag-only parser. `nan_cli compucert` currently
  prints the normal usage line and exits `2`.
- NaNLMind's own CLI (`src/main.cpp` -> `build/nanlm-universal`) has a `verify`
  subcommand but also no certificate command. It is not the canonical NaN0S CLI.
- The NaN16 universality certificate is the Coq VM certificate at
  `formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json`
  (`schema: nanlm.coq-nan16-vm-certificate/1`).
- A safe first implementation now exists:
  `python3 tools/nan0s_compucert.py`
  It performs 92 offline checks against the archived certificate snapshot and
  reports `COMPUCERT: PASS` when the worktree matches the manifest.
- Important live-worktree note: concurrent uncommitted Coq work appeared at
  19:05 local time (not made by this subagent) and is actively changing sources
  and `.vo` objects. The verifier correctly fails closed on that drift. At 19:08
  the live tree reported 84 passed, 8 failed; at 19:10, with `coqc` still
  running, 75 passed, 17 failed. The exact count moves while the build runs.
  See §6.4 and §8.
- Recommended integration is a thin `compucert` / `verify-cert` dispatch in
  `nan_cli.c` that execs a helper, **not** a JSON parser embedded in the C VM.
  That dispatch is intentionally **not** implemented yet; it edits an existing
  CLI file and deserves a separate review.

First command:

```sh
cd /data/data/com.termux/files/home/NaNLMind
python3 tools/nan0s_compucert.py
```

Expected tail when the worktree matches the archived manifest (recorded
19:03-19:07, before the concurrent rebuild):

```text
checks:      92 passed, 0 failed, 0 warnings

COMPUCERT: PASS
```

Expected tail on the current live worktree while concurrent Coq work is in
progress (recorded 19:08):

```text
checks:      84 passed, 8 failed, 0 warnings
...
COMPUCERT: FAIL
```

The second result is the verifier doing its job: the archived certificate no
longer matches the live tree. It is not a verifier bug and not a certificate
failure by itself.

---

## 1. CLI entry points found

### 1.1 Canonical NaN0S CLI (the real NaN0S CLI)

| Item | Exact path / value |
| --- | --- |
| Source | `/data/data/com.termux/files/home/nan0s_work/aarch64/android/tools/nan_cli.c` |
| Build file | `/data/data/com.termux/files/home/nan0s_work/aarch64/android/Makefile` |
| Build command | `make -C /data/data/com.termux/files/home/nan0s_work/aarch64/android` |
| Binary | `/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli` |
| Entry point | `int main(int argc, char **argv)` at line 113 |
| Argument loop | lines 118-146; unknown argument prints usage and returns `2` at line 145 |
| Required input | `--img` or `--nannet-train`; otherwise returns `2` at line 147 |
| Current command families | flags only: `--img`, `--steps`, `--keys`, `--dump-text`, `--state-out`, `--checkpoint`, `--disk`, `--guest-script`, etc. |
| Certificate support | none |

Empirical check (no `--img` needed to see the dispatch behaviour):

```sh
/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli compucert
# prints: usage: nan_cli [--img f] ...
# rc=2
```

`grep -n 'compucert\|verify-cert\|certificate'` over that source and the rest of
the canonical NaN0S tree returns no hit.

### 1.2 Older NaN0S copies

These are older branches/checkouts of the same CLI. Neither has a certificate
command.

| Copy | Source | Binary | Notes |
| --- | --- | --- | --- |
| `nan0s_integration` | `/data/data/com.termux/files/home/nan0s_integration/aarch64/android/tools/nan_cli.c` | `/data/data/com.termux/files/home/nan0s_integration/aarch64/android/nan_cli` | older, smaller flag set |
| `nan0s_prev` | `/data/data/com.termux/files/home/nan0s_prev/aarch64/android/tools/nan_cli.c` | `/data/data/com.termux/files/home/nan0s_prev/aarch64/android/nan_cli` | older checkout |

### 1.3 NaNLMind CLI (not the canonical NaN0S CLI)

| Item | Exact path / value |
| --- | --- |
| Source | `/data/data/com.termux/files/home/NaNLMind/src/main.cpp` |
| Usage text | `usage()` begins at line 1267 |
| Dispatch | `main()` begins at line 1313; command chain ends at line 1358 |
| Existing `verify` | line 1333: `if (cmd == "verify") return cmd_verify();` |
| Build target | `Makefile` line 19: `CLI := $(BUILD)/nanlm-universal`; link rule line 63 |
| `verify` target | `Makefile` lines 343-344: `./$(CLI) verify` |
| Binary | `/data/data/com.termux/files/home/NaNLMind/build/nanlm-universal` |
| Certificate support | none |

This CLI links the pinned NaN0S core from `third_party/nan0s` (`Makefile` lines
16-18). In this checkout `third_party/` is excluded by sparse-checkout, so the
binary cannot currently be built without restoring that directory:

```sh
cd /data/data/com.termux/files/home/NaNLMind
git sparse-checkout add third_party   # would restore the pinned snapshot
make -j2                              # then builds build/nanlm-universal
```

That restore was **not** performed in this scope.

### 1.4 Pinned NaN0S snapshot used by NaNLMind

`third_party/nan0s` is a vendored, read-only snapshot, not a second CLI:

- `third_party/nan0s/SOURCE.json` pins
  `dcb828433f524c0ea6b3035d85f046b75ebf8ac6` from
  `https://github.com/shemshallah/nan0s.git`.
- 13 core/assembler files are vendored, plus `LICENSE`, `README.md`, and
  `SOURCE.json`.
- The snapshot has no CLI of its own; `nan_cli.c` lives in the canonical NaN0S
  checkout, not in this vendored subset.
- In `/data/data/com.termux/files/home/nan0s_work`, `third_party/` contains
  `nan16-libc`, `sqlite`, and `tinycc`; there is no `third_party/nan0s`.

### 1.5 Search result for the requested locations

- `third_party/nan0s` in NaNLMind is the pinned core/assembler snapshot
  (13 vendored files plus metadata). It has no `nan_cli.c` and no certificate
  command; the CLI is not part of the vendored subset.
- `mth/` in NaNLMind contains NaN16 `.nas` fixtures and drivers, not a CLI.
  There is no `nan_cli` entry point there.
- `nan_cli` references resolve to the canonical checkout and the two older
  copies in §1.1-§1.2. None of them has `compucert`, `verify-cert`, or
  certificate JSON/hash verification.

### 1.6 Certificate artifacts

| Artifact | Exact path |
| --- | --- |
| Manifest | `/data/data/com.termux/files/home/NaNLMind/formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json` |
| Statement | `.../nan16_run_halting_equivalence_canonical.statement.txt` |
| Assumptions | `.../nan16_run_halting_equivalence_canonical.assumptions.txt` |
| Proof term | `.../nan16_run_halting_equivalence_canonical.proofterm.txt` |
| `coqchk` summary | `.../nan16_run_halting_equivalence_canonical.coqchk.summary.txt` |
| Full `coqchk` log | `.../nan16_run_halting_equivalence_canonical.coqchk.txt.gz` |
| Coq source | `formal/utm/MinskyNaN16Universality.v` |
| Coq object | `formal/utm/MinskyNaN16Universality.vo` |
| Repro script | `formal/utm/certificates/nan16-vm/reproduce.sh` |
| Literal fixture | `mth/tests/mth_minsky_test.nas` |
| Canonical table include | `tests/minsky_table.inc` |

All paths above are relative to `/data/data/com.termux/files/home/NaNLMind`
unless absolute.

Manifest SHA-256 observed at 19:12 (use this only if the manifest is still
unchanged):

```text
1ac319578c9f80d3c51f41e7dc17c502ae17e096b3703a07c39033f35b72ac45
```

---

## 2. What the certificate actually is

The manifest is `nanlm.coq-nan16-vm-certificate/1` for:

```text
NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical
```

Recorded status:

- `assumptions`: `[]`
- `assumptions_text`: `Closed under the global context`
- `coqchk_status`: `Modules were successfully checked`
- `coq_version`: `8.20.1`
- `hashes`: 9 top-level anchors
- `project_dependencies`: 25 source/`.vo` pairs
- `supporting_theorems`: 3
- `not_proved`: explicit non-claims
- `window_note`: the left window `K` is existential and may grow with native
  time `t`

The theorem is about the **Coq NaN16 VM model** of the fixed 23x8 fixture. It is
explicitly **not**:

- a refinement of `third_party/nan0s/core/nan16.c` or the NaN0S VM;
- a proof that the assembler or assembled `.nas` image matches the Coq blocks;
- a literal assembled-address theorem (`300..303` / table base `304` in Coq vs
  labels `99..104` / table base `104` in the `.nas`);
- a total run-time-independent encoder;
- a proof of the literal 100-step fixture `PASS` path.

These are recorded in the manifest's `not_proved` field and in
`formal/utm/certificates/nan16-vm/README.md`. A verifier must repeat this scope
note rather than upgrade the claim.

### 2.1 "Executing" the certificate has three distinct meanings

1. **Offline integrity verification** (default): read the manifest, hash the
   archived artifacts, check the statement/assumptions/`coqchk` text. No Coq
   needed. This is what `tools/nan0s_compucert.py` does.
2. **Kernel recheck** (online): run `coqchk` on
   `formal/utm/MinskyNaN16Universality.vo` with Coq 8.20.x. This rechecks the
   compiled proof object, not the NaN0S C implementation.
3. **Executable fixture evidence**: run the native NaN16 fixture through
   `nan_cli`/`tools/run_nan16_fixtures.py`. This is conformance evidence, not
   the Coq theorem, and it does not close the refinement gap.

`compucert` should make the mode explicit and must not conflate (1), (2), or
(3).

---

## 3. How to add `compucert` / `verify-cert`

### 3.1 Recommended shape for canonical `nan_cli`

`nan_cli` is a C program with a flat flag loop and no subcommand dispatcher.
Add a **pre-dispatch** at the top of `main()` before the existing loop:

```c
/* compucert / verify-cert: delegate before the NaN16 image parser. */
if (argc >= 2 && (!strcmp(argv[1], "compucert") ||
                  !strcmp(argv[1], "verify-cert"))) {
    const char *helper = getenv("NAN0S_COMPUCERT");
    if (!helper || !*helper) helper = "nan0s-compucert";
    argv[1] = (char *)helper;
    execvp(helper, &argv[1]);
    fprintf(stderr, "nan_cli: cannot exec %s: %s\n", helper, strerror(errno));
    return 127;
}
```

Notes:

- Put this before the `--img` requirement at line 147, so `nan_cli compucert`
  does not ask for an image.
- `execvp` preserves the rest of the arguments and keeps the VM CLI unchanged.
- `NAN0S_COMPUCERT` lets a checkout/tests point at the helper without installing
  it.
- Return `127` for "helper missing", not `2` ("bad VM invocation").
- Add `#include <errno.h>` and `#include <unistd.h>` if not already present
  (`unistd.h` is already included).
- Optionally accept `--compucert` as a flag alias, but do not make it the only
  spelling.

Why a helper and not a C implementation first:

- `nan_cli.c` currently has no JSON parser, no SHA-256 helper, no gzip reader,
  and no `coqchk` invocation path. Embedding all of that in the VM CLI adds a
  large dependency surface to a small, security-sensitive C program.
- The helper is a new file. It can be Python for the first version, then a small
  native binary later if a Python dependency is unacceptable.
- The VM path stays byte-for-byte unchanged when `compucert` is not requested.

Helper placement options:

```text
/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan0s-compucert
/data/data/com.termux/files/home/nan0s_work/tools/nan0s-compucert
```

The first is easiest for a binary installed next to `nan_cli`; the second is
easier for a shell wrapper. `PATH` and `NAN0S_COMPUCERT` cover both.

### 3.2 Alternative: native C module

If the helper process is not acceptable:

1. Add `nan_compucert.c` / `nan_compucert.h` in
   `aarch64/android/tools/` or `aarch64/android/core/`.
2. Add it to `SRC` in `aarch64/android/Makefile`.
3. Implement a minimal JSON reader (or a strict line-oriented manifest reader
   for this one schema), SHA-256, optional gzip, and a `coqchk` subprocess.
4. Dispatch with `return nan_compucert_main(argc - 1, argv + 1);`.

This is more work and more risk than the helper. It should be a second phase,
not the first implementation.

### 3.3 Alternative: NaNLMind `nanlm-universal` subcommand

If the intended product surface is NaNLMind's CLI rather than canonical
`nan_cli`, add:

```cpp
if (cmd == "compucert" || cmd == "verify-cert")
    return nanlm::compucert_cli(argc, argv);
```

to `src/main.cpp` (after the `verify` line), declare `nanlm::compucert_cli` in a
new header, implement it in a new `src/compucert.cpp`, add that source to
`LIB_SRC` in `Makefile`, and add a usage line. This is the most natural
subcommand surface, but:

- it is **not** the canonical NaN0S CLI;
- it requires restoring sparse `third_party/` to build;
- it edits existing C++ files, so it is out of scope for the "new file only"
  first step.

### 3.4 Recommendation

1. Keep `nan_cli.c` unchanged for now.
2. Ship `tools/nan0s_compucert.py` as the verifier/backend.
3. In a separate review, add the 10-line `execvp` dispatch above and install a
   `nan0s-compucert` helper (a two-line shell wrapper around the Python file is
   enough on Termux/Linux).
4. Only then consider a native C implementation.

---

## 4. What `compucert` must check

### 4.1 Certificate JSON schema

Required top-level fields for this schema:

| Field | Required value / shape |
| --- | --- |
| `schema` | exactly `nanlm.coq-nan16-vm-certificate/1` |
| `theorem` | exactly `NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical` |
| `coq_module` | exactly `NaNLM.MinskyNaN16Universality` |
| `coq_source` | repository-relative `formal/utm/MinskyNaN16Universality.v` |
| `coq_vo` | repository-relative `formal/utm/MinskyNaN16Universality.vo` |
| `statement_file` | existing statement text file |
| `assumptions_file` | existing assumptions text file |
| `proof_term_file` | existing proof-term text file |
| `coqchk_summary_file` | existing summary text file |
| `coqchk_log_file` | existing gzip transcript |
| `assumptions` | `[]` |
| `assumptions_text` | exactly `Closed under the global context` |
| `coqchk_status` | exactly `Modules were successfully checked` |
| `coq_version` | recorded version string (currently `8.20.1`) |
| `source_sha256` | 64-hex SHA-256 of `coq_source` |
| `vo_sha256` | 64-hex SHA-256 of `coq_vo` |
| `hashes` | non-empty object of basename -> 64-hex SHA-256 |
| `project_dependencies` | non-empty list of `{module, source, source_sha256, vo_sha256}` |
| `supporting_theorems` | at least the three expected `NaNLM.MinskyNaN16Universality.*` names |
| `scope` | non-empty text |
| `window_note` | non-empty text |
| `not_proved` | non-empty list; print the first entry |

The verifier should fail closed on missing/mistyped fields rather than guess.

### 4.2 Statement and assumptions files

Check all of:

- The statement file exists and its SHA-256 matches the manifest.
- The statement contains the theorem short name
  `nan16_run_halting_equivalence_canonical`.
- The statement still has the expected `forall ... iff ...` shape.
- The assumptions file exists and its SHA-256 matches.
- The assumptions file is exactly `Closed under the global context`.
- The three supporting assumption files are also exactly closed:
  `nan16_source_halt_to_vm.assumptions.txt`,
  `nan16_vm_halt_to_source.assumptions.txt`,
  `nan16_run_halting_equivalence.assumptions.txt`.
- The proof-term file is non-empty and names the theorem.
- The `coqchk` summary contains both:
  - `checking cst:NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical`
  - `Modules were successfully checked`
- The gzip transcript contains the same two strings.

Important nuance: the manifest's `coqchk_context_axioms` lists
`Coq.Logic.FunctionalExtensionality.functional_extensionality_dep`. This is a
module-cone fact in the full `coqchk` context summary, **not** an assumption of
the certified theorem. Do not turn that field into a failure; use the
`Print Assumptions` files for the theorem's exact assumption set. The manifest
already contains this note.

### 4.3 Precomputed hashes

Verify every hash that the manifest records:

- 9 top-level `hashes` anchors, including:
  - `MinskyNaN16Universality.v`
  - `MinskyNaN16Universality.vo`
  - the statement, assumptions, proof term, `coqchk` summary, and `coqchk` gzip
  - `mth_minsky_test.nas`
  - `minsky_table.inc`
- `source_sha256` and `vo_sha256` for the main module.
- 25 project-dependency source/`.vo` pairs: each `source` and its `.vo`.

Path resolution rules for the basenames in `hashes`:

| Basename kind | Search locations |
| --- | --- |
| `.v` / `.vo` | repo root, `formal/utm`, exact manifest path |
| certificate text/gzip | manifest directory, default `formal/utm/certificates/nan16-vm` |
| `mth_minsky_test.nas` | repo root, `mth/tests` |
| `minsky_table.inc` | repo root, `tests` |

Fail on an unresolvable basename. Do not silently skip a hash because a file
was renamed.

Trust-anchor caveat: if the verifier reads the expected hashes from the same
manifest, it detects corruption/drift but not a malicious rewrite of the
manifest. Use one of these for a stronger anchor:

- pass `--expect-cert-sha256` from a reviewed commit/tag (the verifier supports
  this), or
- sign the manifest / record its hash in a release artifact, or
- rely on the reviewed git commit as the trust boundary.

The first implementation supports `--expect-cert-sha256`; no hash is hardcoded,
so certificate regeneration does not require editing the verifier.

### 4.4 `.vo` availability

`formal/utm/*.vo` is git-ignored (`*.vo` in
`formal/utm/certificates/nan16-vm/.gitignore` and the Coq build ignore rules).
A fresh clone therefore has the source/text artifacts but not the compiled
objects.

- Default full mode: require every `.vo` recorded in the manifest. This is the
  honest "all archived anchors present" mode.
- `--allow-missing-vo`: skip missing `.vo` files with warnings. This checks the
  source/text half only and must say so. On a fresh checkout the current
  verifier reports 65 passed, 27 warnings, 0 failed.
- `--coqchk`: requires the main `.vo`; do not run it with `--allow-missing-vo`
  and expect a kernel result.

### 4.5 Optional `coqchk` recheck

Command (from `formal/utm`):

```sh
coqchk -o -Q . NaNLM MinskyNaN16Universality.vo
```

Checks:

- `coqchk` is on `PATH` (or fail with a clear message under
  `--require-coqchk`).
- Exit status is `0`.
- Output contains `Modules were successfully checked`.
- Output contains
  `checking cst:NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical`.
- Optionally, `coqchk --version` matches the manifest's `coq_version` under
  `--strict-version`.

This is a kernel check of the archived `.vo`, not a rebuild. For a full
reproduce, use `formal/utm/certificates/nan16-vm/reproduce.sh`, which runs
`coqc` and `coqchk` and rewrites the raw artifacts. `compucert` must not rewrite
anything.

### 4.6 What `compucert` must not do

- Do not parse or type-check the proof term semantically; hash + text checks are
  enough for the archived-artifact verifier.
- Do not claim the theorem from a hash match. A hash match only says the
  archived files are the ones recorded.
- Do not treat the `coqchk` module-cone axiom as a theorem assumption.
- Do not claim a refinement of `third_party/nan0s/core/nan16.c` or the assembled
  `.nas` image.
- Do not check a fixed `run100` count or the literal fixture `PASS` path; the
  certificate does not claim those.
- Do not regenerate or edit the certificate during verification.

---

## 5. Offline vs online Coq dependency

| Mode | Command | Coq needed | What it establishes | Current local result |
| --- | --- | --- | --- | --- |
| Offline, full | `python3 tools/nan0s_compucert.py` | no | Manifest schema, statement/assumptions/`coqchk` text, all 9 anchors, 25 dependency source/`.vo` hashes | 92 passed, 0 failed, 0 warnings on the archived snapshot; live tree fails with moving source/`.vo` drift (84/8 at 19:08, 75/17 at 19:10; §6.4) |
| Offline, source/text only | `python3 tools/nan0s_compucert.py --allow-missing-vo` | no | Same but skips absent `.vo`; not a full certificate check | 65 passed, 0 failed, 27 warnings in a temp no-`.vo` tree |
| Online kernel recheck | `python3 tools/nan0s_compucert.py --coqchk` or `--require-coqchk` | yes, `coqchk` 8.20.x | Offline checks plus a fresh `coqchk` run on the `.vo` | `coqchk` is not installed on this Termux host; `--coqchk` warns, `--require-coqchk` fails |
| Full rebuild/reproduce | `bash formal/utm/certificates/nan16-vm/reproduce.sh` | yes, `coqc` + `coqchk` | Regenerates the proof object and raw certificate text | not run here |

Offline is the default because:

- It works on this Android/Termux host with Python 3 only.
- It does not require a multi-hundred-megabyte Coq install.
- It still catches stale `.v`/`.vo` pairs, edited statements, edited assumptions,
  missing transcripts, and manifest drift.
- It is honest about the gap: no `.vo` means no compiled-proof anchor.

Online mode is opt-in and never downloads anything. If `coqchk` is unavailable,
the command warns in `--coqchk` mode and fails in `--require-coqchk` mode. The
only supported route in this environment is the existing Debian proot setup:

```sh
proot-distro login debian -- bash formal/utm/certificates/nan16-vm/reproduce.sh
```

or, for a manual kernel check:

```sh
proot-distro login debian -- bash -lc \
  'cd /data/data/com.termux/files/home/NaNLMind/formal/utm && \
   coqchk -o -Q . NaNLM MinskyNaN16Universality.vo'
```

Do not auto-install Coq or fetch anything from the network from `compucert`.

---

## 6. Minimal first implementation (done)

### 6.1 New file

`/data/data/com.termux/files/home/NaNLMind/tools/nan0s_compucert.py`

- Executable, Python 3.10+ standard library only (this host runs 3.14).
- No existing CLI, Makefile, Coq file, certificate file, or `third_party` file
  was changed.
- It is a standalone backend/wrapper: it can be wired into `nan_cli` later
  without changing the verification logic.

### 6.2 What it checks

- Exact schema, theorem, module, required fields, empty assumptions, closed
  assumptions text, recorded `coqchk` status and version.
- Statement, assumptions, proof-term, `coqchk` summary, and gzip transcript
  existence, hashes, and required theorem/status strings.
- All three supporting `Print Assumptions` files.
- All 9 top-level hash anchors and all 25 dependency source/`.vo` hashes.
- Optional pin of the manifest itself with `--expect-cert-sha256`.
- Optional `coqchk` execution with `--coqchk` / `--require-coqchk`.
- Optional JSON report with `--json`, verbose per-check output with `-v`.

It prints the scope disclaimer and the first `not_proved` entry after the
result, so a PASS cannot be mistaken for a NaN0S refinement claim.

### 6.3 Usage

```sh
cd /data/data/com.termux/files/home/NaNLMind

# default offline verification (92 checks)
python3 tools/nan0s_compucert.py

# machine-readable
python3 tools/nan0s_compucert.py --json

# pin the exact reviewed manifest
python3 tools/nan0s_compucert.py \
  --expect-cert-sha256 1ac319578c9f80d3c51f41e7dc17c502ae17e096b3703a07c39033f35b72ac45

# source/text only on a fresh checkout without .vo
python3 tools/nan0s_compucert.py --allow-missing-vo

# kernel recheck when Coq is on PATH
python3 tools/nan0s_compucert.py --coqchk
python3 tools/nan0s_compucert.py --require-coqchk --strict-version
```

Exit codes: `0` pass, `1` verification failure, `2` usage error.

### 6.4 Observed results

Immediately after implementation, the live worktree still matched the archived
manifest:

```text
# 19:03-19:07 local time
checks:      92 passed, 0 failed, 0 warnings
COMPUCERT: PASS
```

The same result was reproduced at 19:07 from a clean `git archive HEAD` plus
the `.vo` objects that were present at that moment. That exact recipe no longer
reproduces 92 now, because the concurrent rebuild has changed several `.vo`
files. The command shape was:

```sh
T=/data/data/com.termux/files/usr/tmp/opencode/compucert_head
rm -rf "$T" && mkdir -p "$T"
cd /data/data/com.termux/files/home/NaNLMind
git archive HEAD | tar -x -C "$T"
cp formal/utm/*.vo "$T/formal/utm/"       # only the 19:07 .vo objects
python3 tools/nan0s_compucert.py \
  --root "$T" \
  --cert "$T/formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json"
# 19:07 result: checks: 92 passed, 0 failed, 0 warnings; COMPUCERT: PASS
```

To re-verify the archived snapshot later, check out the certificate's commit in
a clean worktree and build or restore the matching `.vo` objects first. A
clean source/text-only check is always possible with `--allow-missing-vo`.
At 19:10, a clean `git archive HEAD` checked that way still reported 65 passed,
0 failed, 27 warnings. So the committed manifest/text half is intact; the live
failures are driven by the concurrent Coq source/`.vo` rewrite, not by the
archived certificate text. At 19:12, the preserved 19:07 temp snapshot
(committed HEAD plus the `.vo` objects from that moment) still reported
92 passed, 0 failed, 0 warnings. That is the archived-certificate result; the
live tree is the moving one.

Then concurrent work (another process/session, not this subagent) started
rewriting the Coq layout at 19:05. By 19:08 it had modified seven tracked files
and rebuilt at least three `.vo` objects:

```text
M formal/utm/MinskyNaN16Action.v
M formal/utm/MinskyNaN16Prelude.v
M formal/utm/MinskyNaN16RunClosed.v
M formal/utm/MinskyNaN16RunConcrete.v
M formal/utm/MinskyNaN16StepOk.v
M formal/utm/MinskyNaN16Universality.v
M formal/utm/check_minsky_nan16_step.py
```

The changes pin the formerly abstract Coq control cells (`300..303`, table base
`304`) to the literal fixture labels (tbase `99`, state `100`, head `101`, halt
`102`, table `104`), and several rebuilt `.vo` files no longer match the
manifest. The live-tree verifier now correctly reports:

```text
# 19:08 local time, while the concurrent rebuild is in progress
checks:      84 passed, 8 failed, 0 warnings
COMPUCERT: FAIL
```

The count moves as the concurrent `coqc` run proceeds: at 19:10, with `coqc`
still active, it was 75 passed and 17 failed. Treat any specific count as a
snapshot, not a stable contract; the invariant is that source/`.vo` hash drift
fails closed.

This is the intended fail-closed behaviour. Do not revert the concurrent work
to make the verifier green. If those edits are intended, they need their own
`coqc`/`coqchk` completion, certificate regeneration, and an intentional
manifest/anchor update.

Failure paths exercised without modifying repository files:

- wrong `--expect-cert-sha256` -> `1 failed`, `COMPUCERT: FAIL`, rc 1;
- `--require-coqchk` with no `coqchk` -> `1 failed`, rc 1;
- a temp manifest with a flipped statement hash -> the statement hash check
  fails, rc 1;
- a temp tree with all source/text artifacts but no `.vo` and
  `--allow-missing-vo` -> 65 passed, 27 warnings, rc 0.

### 6.5 Why this is safe

- No VM code path changed. `nan_cli --img ...` still does exactly what it did.
- This subagent did not edit any Coq file, certificate artifact, or CLI source.
  Concurrent external edits are detected by the hash checks; they are not
  touched or reverted.
- No claim promoted; the verifier only checks archived artifacts.
- The `.vo`/source hash checks fail closed by default.
- The helper can be removed with a single file deletion; no build dependency was
  added.

---

## 7. Integration sequence and acceptance criteria

### Phase 1 (done): standalone offline verifier

Acceptance:

- `python3 tools/nan0s_compucert.py` exits 0 when the worktree matches the
  archived manifest (verified from a clean `git archive HEAD` plus the matching
  `.vo` objects at 19:07).
- It exits 1 on a flipped hash, a wrong manifest pin, a missing required
  artifact, or live worktree drift. The current live tree exits 1 because of
  the concurrent Coq rebuild described in §6.4; that is expected.
- It never edits a file.
- It prints the scope/non-claim note.

### Phase 2: add `compucert` dispatch to canonical `nan_cli`

Changes:

- Edit `aarch64/android/tools/nan_cli.c` with the `execvp` pre-dispatch.
- Add a helper file next to the binary, e.g.
  `aarch64/android/nan0s-compucert` (a two-line shell wrapper around
  `tools/nan0s_compucert.py`, or a self-contained verifier).
- No change to `SRC` in the Makefile if the helper is a script.

Acceptance:

```sh
make -C /data/data/com.termux/files/home/nan0s_work/aarch64/android
/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli compucert
# rc=0, COMPUCERT: PASS
/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli verify-cert
# rc=0, same result
/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli --img ...
# unchanged VM behavior
```

Also test the failure path: remove/rename the helper and confirm
`nan_cli compucert` prints a clear error and returns `127` rather than falling
through to the VM usage text.

### Phase 3: optional native implementation

Only if a Python dependency is not acceptable:

- implement the manifest/hash/text checks in C, or compile the Python verifier
  into a small helper;
- keep the same output/exit-code contract;
- add a tamper test that flips one hash in a temp manifest;
- keep `coqchk` optional, not a hard build dependency.

### Phase 4: CI

- Normal CI: run the offline verifier with the reviewed manifest pin. This needs
  no Coq.
- Coq CI: run `--require-coqchk --strict-version` or
  `reproduce.sh` in the Coq 8.20 environment.
- On certificate regeneration, update the pin intentionally in the reviewed
  commit; do not auto-update it from the verifier.

### Non-goals

- No Coq source modifications.
- No certificate regeneration or claim promotion.
- No change to `third_party/nan0s` vendored files.
- No claim that the Coq VM model refines the NaN0S C VM, the assembler, the
  literal `.nas` addresses, the 100-step fixture, or a total encoder.

---

## 8. Risks and open questions

1. **Which CLI is the product surface?** The canonical NaN0S `nan_cli` is
   flag-only. `nanlm-universal` is the only CLI with a subcommand table, but it
   is NaNLMind's CLI, not NaN0S's. This plan assumes the canonical `nan_cli` is
   the target; the `nanlm-universal` option is documented separately in §3.3.
2. **C vs helper.** A native C `compucert` needs JSON, SHA-256, gzip, and
   `coqchk` plumbing. The helper keeps that out of the VM. If a single static
   binary is required, budget for a real parser and tests.
3. **`.vo` availability.** A fresh clone cannot pass full offline mode until
   Coq builds the objects. `--allow-missing-vo` is explicit about the downgrade.
4. **Manifest self-hash.** The manifest records artifact hashes, not its own.
   For a strong anchor, pass `--expect-cert-sha256` from a reviewed commit/tag
   or sign the manifest.
5. **Coq version drift.** `coqchk` should be 8.20.x for this `.vo`.
   `--strict-version` enforces the recorded string; otherwise a mismatch is a
   warning.
6. **Path resolution.** The manifest uses basenames for several anchors
   (`MinskyNaN16Universality.v`, `mth_minsky_test.nas`, `minsky_table.inc`,
   certificate files). The verifier resolves them against known directories and
   fails if a basename is ambiguous/missing.
7. **Canonical checkout is dirty.** `/data/data/com.termux/files/home/nan0s_work`
   currently has unrelated local modifications (`aarch64/android/core/nan16.c`,
   tests, `src/native64/s1_kabi.c`, `tools/kabi64_gate.sh`) and untracked
   `spec/PROCESS_MODEL.md` / `src/prog/kabi_proc_demo.nas`. Do not fold those
   into any compucert change; review them separately.
8. **NaNLMind worktree Coq drift (observed during this task).** At 19:05,
   concurrent work (not this subagent) began pinning the Coq control-cell
   constants to literal fixture addresses in:
   `formal/utm/MinskyNaN16Action.v`, `MinskyNaN16Prelude.v`,
   `MinskyNaN16RunClosed.v`, `MinskyNaN16RunConcrete.v`,
   `MinskyNaN16StepOk.v`, `MinskyNaN16Universality.v`, plus
   `formal/utm/check_minsky_nan16_step.py`. Several `.vo` objects were also
   rebuilt. The archived certificate manifest still records the pre-edit
   hashes, so live-tree verification fails closed (84/8 at 19:08; 75/17 at
   19:10 while `coqc` was still running). This is correct. If the concurrent layout change is intended, it must finish its
   own Coq build/kernel check and regenerate the certificate; do not mix that
   work with the compucert wrapper or silently update the manifest.
9. **No claim promotion.** Even a fully green `compucert` is an artifact check
   (or a `coqchk` run on the Coq VM model), not a certificate that NaN0S
   executes the fixture. The explicit `not_proved` list remains in force.

---

## 9. Exact paths and first command

### 9.1 Paths

| Purpose | Exact path |
| --- | --- |
| Canonical NaN0S CLI source | `/data/data/com.termux/files/home/nan0s_work/aarch64/android/tools/nan_cli.c` |
| Canonical NaN0S CLI build | `/data/data/com.termux/files/home/nan0s_work/aarch64/android/Makefile` |
| Canonical NaN0S CLI binary | `/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli` |
| Older integration CLI source | `/data/data/com.termux/files/home/nan0s_integration/aarch64/android/tools/nan_cli.c` |
| Older previous CLI source | `/data/data/com.termux/files/home/nan0s_prev/aarch64/android/tools/nan_cli.c` |
| NaNLMind CLI source | `/data/data/com.termux/files/home/NaNLMind/src/main.cpp` |
| NaNLMind CLI binary | `/data/data/com.termux/files/home/NaNLMind/build/nanlm-universal` |
| Certificate manifest | `/data/data/com.termux/files/home/NaNLMind/formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json` |
| Certificate README | `/data/data/com.termux/files/home/NaNLMind/formal/utm/certificates/nan16-vm/README.md` |
| Coq theorem source | `/data/data/com.termux/files/home/NaNLMind/formal/utm/MinskyNaN16Universality.v` |
| Coq kernel object | `/data/data/com.termux/files/home/NaNLMind/formal/utm/MinskyNaN16Universality.vo` |
| Offline verifier (new) | `/data/data/com.termux/files/home/NaNLMind/tools/nan0s_compucert.py` |
| This plan | `/data/data/com.termux/files/home/NaNLMind/NAN0S_COMPUCERT_PLAN.md` |

### 9.2 First command

```sh
cd /data/data/com.termux/files/home/NaNLMind
python3 tools/nan0s_compucert.py
```

Expected when the worktree matches the archived manifest:
`checks: 92 passed, 0 failed, 0 warnings` and `COMPUCERT: PASS` (exit 0).

Current live-tree expectation (concurrent Coq rebuild in progress): exit 1
with source/`.vo` hash drifts, not a verifier error. The count moved from
`84 passed, 8 failed` at 19:08 to `75 passed, 17 failed` at 19:10 while `coqc`
was still running. To check the committed certificate text snapshot, use the
clean-archive recipe with `--allow-missing-vo` in §6.4; to check the compiled
snapshot, restore the matching `.vo` objects first.

### 9.3 First command after Phase 2 (not yet implemented)

```sh
make -C /data/data/com.termux/files/home/nan0s_work/aarch64/android
/data/data/com.termux/files/home/nan0s_work/aarch64/android/nan_cli compucert
```

Until the dispatch and helper are added, `nan_cli compucert` correctly returns
`2` with the normal VM usage line. That is the current, unmodified behaviour.
