# NaN0S / NaN16 ISA Contract (Living)

**Contract ID:** `NAN0S-ISA-1`  
**Revision:** 1 (2026-11-24)  
**Repository revision:** `e8b2cef1ec5bae161f5a2401d70f3dfb009c6e16`  
**Status:** living contract. This document is a coverage snapshot, not a
promise that the ISA, the assembler, the Coq model, or the C oracle will never
change. Pins say what a proof currently covers; a new pin and a delta
obligation are required after every semantic change.

This file supersedes the previously requested `NAN0S_C_SPEC.md` name. There
is no C-refinement claim here. `third_party/nan0s/core/nan16.c` is treated as
a differential/conformance oracle only.

---

## 0. Authority order and non-claims

When artifacts disagree, resolve in this order, then record the resolution as
a delta obligation:

1. **Literally assembled `.nas` program words** produced by the pinned
   `third_party/nan0s/tools/nmk.awk` from the pinned `.nas` source.
2. **The Coq target semantics** `exec_instr` / `run_until` in
   `formal/utm/MinskyNaN16VM.v`, extended as needed to the literal
   instruction stream.
3. **`third_party/nan0s/core/nan16.c`** as a differential oracle, not as the
   implementation being refined.
4. **`third_party/nan0s/core/OPS.md`** as prose cross-check, not authority
   over the pinned code.

### Non-claims

- No theorem says `nan16.c` implements the Coq model or the literal `.nas`
  image.
- No theorem says `nmk.awk` correctly encodes the Coq instruction list.
  Existing checks are source-text transcription gates, not assembler proofs.
- No theorem covers the literal assembled addresses, the literal 100-step
  PASS path, or the `puts` routine. The current certificate explicitly
  excludes these in
  `formal/utm/certificates/nan16-vm/README.md:170-181`.
- C oracle runs are evidence for a differential gate, never a proof.
- This contract does not claim immutability of any artifact.

### Target

The target is:

> **Literal NaN16 program execution refines the Coq `exec_instr` /
> `run_until` model**, under an explicit word/register/flag/memory relation,
> with the C oracle used only to detect drift.

The current Coq theorem
`NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical`
(`formal/utm/MinskyNaN16Universality.v:619-649`) is a **model-level**
theorem. It refines the fixed 23x8 Minsky table into the Coq NaN16 model. It
does not yet connect the model to the literal assembled image.

### At-a-glance pins and first obligations

| Item | Value |
| --- | --- |
| Literal `.nas` pin | `173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e` |
| Assembled image pin | `f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77` |
| `nan16.c` oracle pin | `05d34f61f0ad27f8b642b7023186d9addb456dedd1e30ce9ba6053b840e8fdb2` (not proof-covered) |
| External fixture runner | `nan_cli.c 19a1406e...`, runner core `7ed97760...`, checkout `80bc81db...` (not proof-covered) |
| ISA bundle | `ISA_REV-1 = 68d0950600fca81d31a41157ad43a14213e5c21480de896d2872528a05c6f0f8` |
| Current Coq proof pin | `COQ_MODEL_PIN-1 = 2af802191921c301d62e24617d9f7e08c6aa41a772418dbdc9bd8aa699d55166` (HEAD certificate) |
| First delta obligation | **D-01**: reconcile vendored oracle bytes with `SOURCE.json`/canonical snapshot |
| First ISA-level proof obligation | **ISA-OBL-1**: `fixture_pc0_decode_and_step` (word 0 -> `iMOVI 13 1`, one literal step) |

---

## 1. Pins and current coverage

### 1.1 Artifact pins

`git blob` is the Git object ID; `sha256` is over the exact file bytes at the
repository revision above. The vendored `third_party/nan0s` paths are tracked
but may be absent from a narrow sparse checkout; the hashes below are the
tracked blobs and can be reproduced with `git show HEAD:<path> | sha256sum`.
The Coq rows are the HEAD-certificate versions; the active worktree has
uncommitted edits that are explicitly not covered (section 1.5).

| Role | Path | Git blob | SHA-256 | Bytes |
| --- | --- | --- | --- | ---: |
| Repository | `HEAD` | `e8b2cef1ec5bae161f5a2401d70f3dfb009c6e16` | - | - |
| Literal fixture | `mth/tests/mth_minsky_test.nas` | `b40bdbe62bde1b573fd11401eb4ee12dc307ddc8` | `173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e` | 7,827 |
| Assembler | `third_party/nan0s/tools/nmk.awk` | `4a61326b3ea619873502909736f09cc72d86151d` | `587116bdffc7715d0dffd6846767dbda76a9d14b55085e9ed8ed08cbdfe1009b` | 13,772 |
| ISA prose | `third_party/nan0s/core/OPS.md` | - | `ec7831ffb9a66a0c5b01011cf2410150295d894786bb526ddf28ee672f5d2e02` | 11,106 |
| Oracle core | `third_party/nan0s/core/nan16.c` | `cd71a430836ca5996b66f339eacde749eb166427` | `05d34f61f0ad27f8b642b7023186d9addb456dedd1e30ce9ba6053b840e8fdb2` | 16,740 |
| Oracle API | `third_party/nan0s/core/nan16.h` | `ecde51acdc6cd92fc600ba146e19c682bc53c2bc` | `42f994710eff55bf62b54edd0b3835fd00024d2fc7363576013f6d8048c45aa2` | 6,337 |
| Oracle state | `third_party/nan0s/core/nan16_int.h` | `bebdea8b8e2f657c43c898ae353e3aa45482d60a` | `cd1cea4329f5436c263122373f80a368f1158d0fc95fc89ef6ee5180a72685b0` | 2,593 |
| Coq ISA model | `formal/utm/MinskyNaN16VM.v` | - | `005e8422965122cae5b1727c05ba1e0d6ea1735583e5de7713e7092b96743b87` | - |
| Coq run model | `formal/utm/MinskyNaN16Run.v` | - | `a35a1d6e1ea52f297debca9b4c3e379b80d648da9e54d7c0658f33b78237f85e` | - |
| Coq concrete fixture | `formal/utm/MinskyNaN16RunConcrete.v` | - | `984b3c18b9def2ffa28c63a06c31c82b949ee2e0bc6c1463a9aa4fef2b13db56` | - |
| Coq final theorem | `formal/utm/MinskyNaN16Universality.v` | - | `a101596212b63381af0c04b7941949bf3a63f88e46f35afbc3eb5d8f9dd8bd37` | - |
| Certificate statement | `formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.statement.txt` | - | `d3ee6d5c1e5284d45f31741af35feb0eb8651201e3a28ead919fa18d1a8b8be9` | - |
| Certificate manifest | `formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json` | - | `1ac319578c9f80d3c51f41e7dc17c502ae17e096b3703a07c39033f35b72ac45` | - |

### 1.2 Composite revision hashes

These are convenience hashes, defined exactly. Any file change must bump the
corresponding revision.

```text
ISA_REV-1 = SHA-256 of the sorted lines
  core/OPS.md <sha256>
  core/nan16.c <sha256>
  core/nan16.h <sha256>
  core/nan16_int.h <sha256>
  tools/nmk.awk <sha256>
            = 68d0950600fca81d31a41157ad43a14213e5c21480de896d2872528a05c6f0f8

UPSTREAM_SOURCE_PIN (hashes recorded by SOURCE.json)
            = 0a2fb0c7a09534e4ab5cac8878bf73feb818b8ba4a6b178e9bb04f3adcae71b3
              (uses canonical nan16.c/h/int hashes, not the vendored bytes)

COQ_MODEL_PIN-1 = SHA-256 of these four lines in this exact order
  formal/utm/MinskyNaN16Run.v a35a1d6e1ea52f297debca9b4c3e379b80d648da9e54d7c0658f33b78237f85e
  formal/utm/MinskyNaN16RunConcrete.v 984b3c18b9def2ffa28c63a06c31c82b949ee2e0bc6c1463a9aa4fef2b13db56
  formal/utm/MinskyNaN16Universality.v a101596212b63381af0c04b7941949bf3a63f88e46f35afbc3eb5d8f9dd8bd37
  formal/utm/MinskyNaN16VM.v 005e8422965122cae5b1727c05ba1e0d6ea1735583e5de7713e7092b96743b87
            = 2af802191921c301d62e24617d9f7e08c6aa41a772418dbdc9bd8aa699d55166
              (HEAD-certificate versions; not the uncommitted worktree edits)

ASSEMBLED_IMAGE (LC_ALL=C gawk CMD=emit)
            = f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77
              (4366 words; 141,409 bytes including comments)
```

`COQ_MODEL_PIN-1` is a convenience digest of four core model files, **not**
the full certificate dependency closure. The full closure, including every
`MinskyNaN16*.v` source and `.vo` hash used by the final theorem, is recorded
in `formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json`
(manifest SHA-256 `1ac319...`). Use that manifest when auditing the whole
proof, and this four-file digest only for the core model comparison.

### 1.3 What the current proof actually covers

| Artifact / layer | Current coverage | Evidence |
| --- | --- | --- |
| Fixed 23x8 table data | Transcription-checked 184/184 | `formal/utm/check_minsky_nan16_words.py` |
| Coq table model | Kernel-checked | `MinskyNaN16Words.v`, `nan16_words.certificate.json` |
| Coq NaN16 run model | Kernel-checked at model scope | `nan16_run_halting_equivalence_canonical` |
| Literal `.nas` instruction stream | **Not covered by a Coq theorem** | only source-text gates, `check_minsky_nan16_step.py` |
| Literal assembled image / labels | **Not covered** | certificate README lines 170-181 |
| `nan16.c` implementation | **Not covered; oracle only** | this contract |
| Full fixture PASS path / `puts` | **Not covered** | certificate README lines 170-181 |

**Coverage warning.** The certificate's own scope section says it is not "a
refinement of `third_party/nan0s/core/nan16.c`" and not "a literal
assembled-address theorem." This contract keeps that boundary explicit.

### 1.4 Oracle pin integrity finding (open)

The vendored core is **not byte-identical** to the snapshot recorded in
`third_party/nan0s/SOURCE.json`. The tracked files differ in exactly these
places relative to the canonical commit
`dcb828433f524c0ea6b3035d85f046b75ebf8ac6` at `aarch64/android/core/`:

| File | Vendored (actual) | `SOURCE.json` / canonical | Difference |
| --- | --- | --- | --- |
| `nan16.c` | `05d34f...` | `0ef601...` | `nan_run` argument `uint32_t max_steps` -> `uint64_t`; local `done` `uint32_t` -> `uint64_t` |
| `nan16.h` | `42f994...` | `489fad...` | matching `nan_run` prototype change |
| `nan16_int.h` | `cd1cea...` (2593 B) | `30351a...` (2592 B) | `NAN_WORDS` `0x400000` -> `0x2000000` |

Consequences: the default guest memory is 32M words / 256 MiB in the vendored
file (`NAN_MASK = 0x1FFFFFF`), while `OPS.md` and the canonical snapshot say
4M words / 32 MiB (`MASK = 0x3FFFFF`). The fixture's highest word index is
4365, well below either limit, so the current Minsky run is unaffected, but
any decoder/bounds proof must pin one geometry. See delta obligation
**D-01**.

### 1.5 Certificate pin versus active worktree (open)

The Coq proof of record is the **HEAD certificate** at
`e8b2cef1ec5bae161f5a2401d70f3dfb009c6e16`. Its `Print Assumptions` is
closed and its certificate JSON records the HEAD source hashes. At the time
this contract revision was written, `git status` showed uncommitted edits to
the Coq chain:

```text
M formal/utm/MinskyNaN16Action.v
M formal/utm/MinskyNaN16Prelude.v
M formal/utm/MinskyNaN16RunClosed.v
M formal/utm/MinskyNaN16RunConcrete.v
M formal/utm/MinskyNaN16StepOk.v
M formal/utm/MinskyNaN16Universality.v
M formal/utm/check_minsky_nan16_step.py
```

Those edits are **not covered by the certificate pin**. In particular, HEAD
uses abstract control cells `300..303` and table base `304`, while the active
worktree has an uncommitted literalization to `head=101`, `state=100`,
`halt=102`, `tbase=99`, table `104`. Do not cite the worktree as certified,
and do not mix HEAD and worktree hashes in one proof claim. Re-run
`coqc`/`coqchk`, regenerate the certificate, and commit before using the
literalized version. This is delta **D-10a**.

### 1.6 External runner pin (the actual fixture invocation)

`tools/run_nan16_fixtures.py:153-154` invokes an **external** `nan_cli`, not
the vendored `nan_create` API. The inspected checkout is:

| Role | Path | Pin |
| --- | --- | --- |
| NaN0S checkout | `/data/data/com.termux/files/home/nan0s_work` | commit `80bc81dbf892ca72719882ddd02691f23083785c` |
| CLI source | `aarch64/android/tools/nan_cli.c` | SHA-256 `19a1406e4593281f91313075fa9c6ca5d84d5ec0daa68e55f90f296b80a749ae` (16,246 B) |
| CLI core | `aarch64/android/core/nan16.c` | SHA-256 `7ed977607efb8f57c7bed802f9dffdf349ad3dc1cecd7fe379b59f4839b23d41` (30,272 B) |
| VM header | `aarch64/android/core/nan16.h` | SHA-256 `740ea2cb17fcc3e1903c2566cde815a533432f9bad3023c4a85c906dc742e414` (9,127 B) |
| VM internal header | `aarch64/android/core/nan16_int.h` | SHA-256 `959f90b7b92a70bc34bbe3d943186dddda442cee1cbc0b5a5dacf527b863a022` (2,984 B) |

Decision **D-01** is *restore, do not fork*: these five files were restored
from commit `80bc81d...` into `nan0s_work` with `git show`. The checkout's
current `HEAD` may be later, so the file hashes above, not the `HEAD` id, are
authoritative for the loader gate.

This is a **third** C variant: it differs from both the vendored snapshot
(`05d34f...`) and the canonical `SOURCE.json` snapshot (`0ef601...`). The
fixture runner's default memory request is `words_for_mb(128) = 0x2000000`
words, matching the vendored header's 32M-word geometry, not the 4M-word
`OPS.md` text. The runner uses `nan_create_words`, `nan_load_auto`, and
`nan_run` (see section 9.4). Record which C variant produced any oracle
result; do not merge hashes or step counts across variants.

---

## 2. Word, register, and memory model

### 2.1 NaN16 word width

A guest word is **64 bits** (`uint64_t` in the oracle; `NAN_WORDS * 8` bytes).
Its byte and bit layout is fixed:

```text
byte 0..1   FAR head, big-endian 16-bit
byte 2..5   payload, little-endian 32-bit
byte 6..7   NEAR head, little-endian 16-bit
```

As a raw little-endian `uint64_t`:

```text
w = (uint64_t)near << 48
  | (uint64_t)payload << 16
  | (uint64_t)far_swapped
far_swapped = (far >> 8) | ((far & 0xFF) << 8)
```

Reference: `third_party/nan0s/core/nan16_int.h:22-28`,
`third_party/nan0s/core/nan16.c:216-227`.

Heads and classes (`nan16_int.h:19-21`):

| Head | Class | Valid |
| --- | --- | --- |
| `0x7FF1` | 0 | yes (low nibble 1) |
| `0xFFF1` | 1 | yes |
| `0x7FF8` | 2 | yes (low nibble 8) |
| `0xFFF8` | 3 | yes |

```text
nan_hvalid(h) = ((h & 0x7FF0) == 0x7FF0)
                && ((h & 15) == 1 || (h & 15) == 8)
nan_hcls(h)   = ((h >> 2) & 2) | (h >> 15)
n             = (class(near) << 2) | class(far)     // 0..15
```

`n` is both the predicate selector and, for `BOOL`, the 4-bit truth table.
`nan_mkword(payload, n)` chooses `far = NAN_HEADS[n & 3]` and
`near = NAN_HEADS[(n >> 2) & 3]`.

### 2.2 Architectural state

| State | Width | Meaning | Reset |
| --- | --- | --- | --- |
| `r[0..15]` | 32-bit unsigned | general registers; `r15` is the link register | 0 |
| `pc` | 32-bit unsigned | word index; fetch uses `pc & NAN_MASK` | 0 |
| `k` | `int` | packed flags `k = 2*Z + L`; 0..3 | 0 |
| `halted` | boolean | sticky halt/trap state | 0 |
| `steps` | 64-bit unsigned | retired fetch attempts; `KEY` rewind decrements | 0 |
| `ms` | 32-bit unsigned | host-supplied `TICK` source | 0 |
| `mem` | `NAN_WORDS * 8` bytes | unified code/data/tape memory | zeroed |
| `vram` | 16 MiB | display memory | zeroed |
| `cells[2000]` | 16-bit cells | 80x25 text memory | `0x0720` |

Reference: `nan16_int.h:37-52` (`struct nan_vm`), `nan16.c:69-80`
(`nan_reset`). `nan_set_pc` writes `pc` and clears `halted`
(`nan16.c:147`).

### 2.3 Guest memory geometry

The oracle allocates `NAN_WORDS` 8-byte words (`nan16.c:58`) and uses
`NAN_MASK = NAN_WORDS - 1` (`nan16_int.h:9`). **Two geometries exist in the
pinned artifacts:**

| Source | `NAN_WORDS` | Words | Mask | Bytes |
| --- | ---: | ---: | --- | ---: |
| Vendored `nan16_int.h` (actual) | `0x2000000` | 33,554,432 | `0x1FFFFFF` | 268,435,456 |
| Canonical `SOURCE.json` and `OPS.md` | `0x400000` | 4,194,304 | `0x3FFFFF` | 33,554,432 |

The fixture addresses (`0..4365`, tape image at `4096..4351`) fit in both.
Do not write a proof that silently assumes either; choose one by
**D-01/D-02** and record it in the pin.

Memory rules:

- **Word fetch:** `w = mem[pc & MASK]`. `pc` is a full 32-bit counter, so
  fetch wraps; there is no instruction fault for an out-of-range PC.
- **LD/ST/LDN/BSWAPM word addressing:** index is `(A + imm) & MASK`
  (32-bit `A + imm`, then mask). No alignment fault.
- **LDB/STB byte addressing:** address `ad = A + imm` (32-bit wrap), word
  index `(ad >> 2) & MASK`, byte lane `ad & 3`, little-endian within the
  32-bit payload. Each word exposes 4 payload bytes, not the head bytes.
- **BCOPY/BFILL:** count `B` is a full 32-bit value; every touched address is
  `& MASK`; a huge count can wrap and is O(count) in the oracle.
- **Byte transport:** `nan_write_bytes` / `nan_read_bytes` bound the span by
  `NAN_WORDS * 4` bytes and reject the whole span on overflow
  (`nan16.c:92-117`).
- **Raw word transport:** `nan_write_words_raw` / `nan_read_words_raw` bound
  `first_word` and `word_count` to `NAN_WORDS`, reject short/overflow spans,
  and require a little-endian host (`nan16.c:124-144`).
- **Text loader:** `nan_load_text` requires `idx < NAN_WORDS` before each
  word; it does not validate head bytes (`nan_load.c:25-40`).
- **VRAM:** 16 MiB, clamped; display writes do not alias guest memory
  (`nan16_int.h:16`, `nan16.c:165-205`).

The guest memory is a flat, unified 64-bit-word space. There is no read-only
code page, no stack, no page table, and no trap on data/tape overlap.

---

## 3. Encoding, fetch, decode, and execute

### 3.1 `.nas` text and assembler encoding

`nmk.awk` (`CMD=emit`) emits one text line per word:

```text
NEAR_PAYLOAD_FAR   ; <word-index> <disassembly>
```

The `.nan` loader `nan_load_text` (`nan_load.c:25-40`) converts a line
`AAAA_PPPPPPPP_BBBB` to:

```c
v->mem[idx++] = ((uint64_t)f1 << 48) | ((uint64_t)f2 << 16) | f3;
```

where `f1` is the NEAR head value (`0x7FF1`/`0xFFF1`/`0x7FF8`/`0xFFF8`),
`f2` is the 32-bit payload, and `f3` is the byte-swapped FAR head field
(`0xF17F`/`0xF1FF`/`0xF87F`/`0xF8FF`). The loader does **not** check head
validity, and `.org` only moves the write index; it does not check the bound
until the next word write.

Assembler data directives:

- `.word v1, v2, ...` emits each value as payload with `n = 10`
  (both heads `0x7FF8`).
- `.str "..."` emits UTF-8 bytes, a NUL, zero-pads to 4 bytes, then emits
  each 4-byte group as a little-endian payload with `n = 10`.
- `.org N` pads forward to word index `N`; backward `.org` is rejected by
  `nmk.awk` (`nmk.awk:180-185`).
- `LA r, expr` expands to `MOVI r, low16` plus `MOVHI r, high16`
  (`nmk.awk:209-216, 260-267`).
- `MOVI` immediates must fit in 16 bits (`nmk.awk:299`).
- Predicate suffix `[EQ]`, `[NE]`, `[LT]`, `[GE]`, `[GT]`, `[LE]`,
  `[ALWAYS]`, `[NEVER]` selects `n = 4,3,2,5,1,6,15,0`
  (`nmk.awk:20-21, 278-284`).
- `BOOL.8` sets `n = 8` (truth table `A & B`); the numeric suffix is the
  truth table, not a predicate.

### 3.2 Exact fetch/decode/execute order

`nan_run` is the only interpreter loop (`nan16.c:207-334`). There is **no
separate `step` function**. The order is:

1. If `v->halted`, return `NAN_HALTED` (`nan16.c:213`).
2. While `done < max_steps`: `done++`, `v->steps++` (`nan16.c:214-215`).
3. Fetch `w = mem[pc & MASK]` (`nan16.c:216`).
4. Compute `nh = nan_near(w)`, `fh = nan_far(w)`. If either head is invalid,
   `trap(v, 'G', pc + 1)`, set `halted`, return `NAN_HALTED`
   (`nan16.c:217-218`, trap at `158-163`).
5. `at = pc; pc++` (`nan16.c:219`).
6. `p = (uint32_t)(w >> 16)`, `op = p >> 24`,
   `n = (nan_hcls(nh) << 2) | nan_hcls(fh)` (`nan16.c:220-221`).
7. If `op == 0xFF`: set `halted = 1`, return `NAN_HALTED`. This is
   unconditional and happens **before** predicate and before the
   `op > 0x48` check (`nan16.c:222`).
8. If `op > 0x48`: `trap(v, 'O', pc)`, return `NAN_HALTED`. This is
   unconditional, even if the predicate bit would be zero (`nan16.c:223`).
9. If `op != 0` and `((n >> v->k) & 1) == 0`: skip (continue). The PC has
   already advanced; no trace callback. `BOOL` (`op == 0`) is exempt because
   `n` is its truth table (`nan16.c:224`).
10. Call the trace callback if installed (`nan16.c:225`).
11. Decode operands:
    `d = (p >> 20) & 15`, `a = (p >> 16) & 15`, `imm = p & 0xFFFF`,
    `A = r[a]`, `B = r[imm & 15]` (`nan16.c:226-227`).
12. Execute the `switch (op)` case (`nan16.c:228-329`). A case that traps
    calls `trap(v, 'O', pc)` and returns `NAN_HALTED`.
13. On normal case completion, loop. On budget exhaustion, write `v->pc = pc`
    and return `NAN_BUDGET` (`nan16.c:331-333`).

Trap text is `!` + kind + uppercase hex of the shown PC, minimum four digits,
written to the serial ring and copied to `v->trap` (`nan16.c:158-163`).

`nan_run` return codes (`nan16.h:19-26`):

| Code | Name | Meaning |
| ---: | --- | --- |
| 0 | `NAN_BUDGET` | step budget exhausted; PC points at next instruction |
| 1 | `NAN_WAIT_KEY` | `KEY` with empty ring; PC rewound to the `KEY` |
| 2 | `NAN_VSYNC` | `VSYNC` in graphics mode |
| 3 | `NAN_HALTED` | `HALT` or trap |
| 4 | `NAN_TIME_WAIT` | `TICK` saw 256 unchanged milliseconds |

### 3.3 PC, CALL/RET, and HALT

| Operation | PC behavior | Link (`r15`) |
| --- | --- | --- |
| ordinary op | `pc_after_fetch = old_pc + 1` | unchanged |
| `JMP imm` (`0x0A`) | `pc = imm` (16-bit) | unchanged |
| `CALL imm` (`0x0B`) | `pc = imm` (16-bit) | `r15 = old_pc + 1` |
| `RET` (`0x0C`) | `pc = r15` | unchanged |
| `JMPR a` (`0x0D`) | `pc = A` | unchanged |
| `CALLR a` (`0x2C`) | `pc = A` | `r15 = old_pc + 1` |
| `JMPF` (`0x38`) | `pc = payload & 0xFFFFFF` | unchanged |
| `CALLF` (`0x39`) | `pc = payload & 0xFFFFFF` | `r15 = old_pc + 1` |
| `HALT` (`0xFF`) | `pc = old_pc + 1` in the oracle; `halted = 1` | unchanged |
| trap | `pc = shown` (G: `old_pc + 1`; O: post-increment `pc`) | unchanged |

`r15` is an ordinary register and the only link storage. Nested calls
overwrite it; the fixture saves it with `ST r15,r0,@rlink` at word 29 and
restores it with `LD r15,r0,@rlink` at word 34. There is no stack.

**HALT divergence:** the literal oracle increments `pc` before the `0xFF`
check, so `HALT` at word 28 leaves `pc = 29`. Coq `iHALT`
(`MinskyNaN16VM.v:158-161`) leaves `vm_pc` unchanged at 28. Any refinement
relation must either normalize PC at halt or model the post-increment. This
is **D-06**.

### 3.4 Flags and predicates

`k` is packed as:

```text
k = 2*Z + L
Z = (k >> 1) & 1
L = k & 1
predicate pass = ((n >> k) & 1) == 1
```

Reference: `nan16.c:211` (`SETK`), `224` (bit test); `OPS.md:49-50`.

| `n` | name | pass condition in the oracle |
| ---: | --- | --- |
| 15 | ALWAYS | always |
| 0 | NEVER | never |
| 4 | EQ | `k == 2`, i.e. `Z=1, L=0` |
| 3 | NE | `k == 0` or `k == 1`, i.e. `Z=0` |
| 2 | LT | `k == 1`, i.e. `Z=0, L=1` |
| 5 | GE | `k == 0` or `k == 2`, i.e. `L=0` |
| 1 | GT | `k == 0`, i.e. `Z=0, L=0` |
| 6 | LE | `k == 1` or `k == 2`, i.e. `Z xor L` (excludes `k=3`) |

The Coq `pred_holds` (`MinskyNaN16VM.v:58-68`) agrees with this table only
when `k != 3`. For `k=3` (`Z=1,L=1`), Coq `pEQ`, `pLT`, `pGE`, and `pLE`
return true while the bit test returns false (`pGT` and `pNE` agree at
`k=3`). Normal `CMP`/`SUB` produce `Z=1 => L=0`, so the fixture avoids
`k=3`, but `ADD` carry, `DIV` by zero, and `FCMP` unordered can produce it.
This is **D-07**.

Flag effects by instruction group:

| Group | Z | L |
| --- | --- | --- |
| `BOOL` | `res == 0` | 0 |
| `ADD`, `ADDI` | low 32-bit result == 0 | carry out of bit 31 |
| `SUB` | result == 0 | unsigned `A < B` (borrow) |
| `SHL`, `SHR`, `SAR` | result == 0 | 0 |
| `CMP` | `A == B` | unsigned `A < B` |
| `CMPS` | `A == B` | signed `(int32_t)A < (int32_t)B` |
| `MUL`, `MULH`, `MULHU` | result == 0 | 0 |
| `DIV`, `MOD`, `DIVU`, `MODU` | `B != 0`: result == 0; `B == 0`: `k=3` | `B != 0`: 0; `B == 0`: 1 |
| `FCMP` | ordered and equal | ordered and `A < B`; unordered: `k=3` |
| `CVTFI` | result == 0 | 0 |
| floating `FADD/FSUB/FMUL/FDIV/FSQRT/CVTIF/FEXP/FTANH/FLOG` | 0 | 0 |
| `MOVI`, `MOVHI`, `LD`, `ST`, `LDN`, `STW`, `JMP*`, `CALL*`, `RET`, `NOP`, `VPOKE`, `VPEEK`, `KEY`, `KEYQ`, `TICK`, `BSWAPM`, `PUTC`, `DISPQ`, `DISPSET`, `LDB`, `STB`, `BCOPY`, `BFILL`, `FBINFO`, `VSYNC`, `FBCOPY`, `FBFILL`, ports, `CPUID`, `RDTSC` | unchanged | unchanged |

`DIV`/`MOD` by `-1` are special-cased (`0u - A` and `0`) to avoid signed
overflow UB (`nan16.c:275-281`). `DIV`/`DIVU` by zero write 0; `MOD`/`MODU`
by zero write `A`; all four set `k=3` and still write `r[d]`.

**Signed right-shift assumption:** `SAR` (`nan16.c:238`) and the high half
of `MULH` (`nan16.c:273`) use right shift of a negative signed value. The C
standard leaves that implementation-defined; the pinned ARMv7/AArch64/x86
targets implement arithmetic shift. The Coq model must state this explicitly
or define `SAR`/`MULH` bitwise. This is covered by **D-05** and the
signedness gate in **G9**.

---

## 4. Complete instruction inventory

`op` is the high byte of the payload (`p >> 24`). `d = (p>>20)&15`,
`a = (p>>16)&15`, `imm = p & 0xFFFF`, `A = r[a]`,
`B = r[imm & 15]`. All line references are to the pinned
`third_party/nan0s/core/nan16.c`.

### 4.1 Core moves and integer arithmetic

| `op` | mnemonic | `.nas` form | exact effect (oracle) | flags/PC |
| ---: | --- | --- | --- | --- |
| `0x00` | `BOOL` | `BOOL[.n] d,a,b` | truth table `n`: bit0 `~(A\|B)`, bit1 `~A&B`, bit2 `A&~B`, bit3 `A&B`; `r[d]=res` | `Z=res==0`, `L=0`; never predicated |
| `0x01` | `MOVI` | `MOVI d,imm` | `r[d]=imm` (zero-extended 16-bit) | unchanged |
| `0x02` | `MOVHI` | `MOVHI d,imm` | `r[d]=(r[d]&0xFFFF)\|(imm<<16)` | unchanged |
| `0x03` | `ADD` | `ADD d,a,b` | `s=(uint64)A+B; r[d]=(uint32)s` | `Z=low==0`, `L=s>>32` |
| `0x04` | `SUB` | `SUB d,a,b` | `r[d]=A-B` modulo 2^32 | `Z=res==0`, `L=A<B` |
| `0x05` | `SHL` | `SHL d,a,imm` | `r[d]=A<<(p&31)` modulo 2^32 | `Z`, `L=0` |
| `0x06` | `SHR` | `SHR d,a,imm` | `r[d]=A>>(p&31)` logical | `Z`, `L=0` |
| `0x07` | `CMP` | `CMP a,b` | no write | `Z=A==B`, `L=A<B` unsigned |
| `0x20` | `MUL` | `MUL d,a,b` | `r[d]=(A*B)&0xFFFFFFFF` | `Z`, `L=0` |
| `0x21` | `MULH` | `MULH d,a,b` | signed high 32 bits of `(int64)(int32)A*(int32)B` | `Z`, `L=0` |
| `0x22` | `MULHU` | `MULHU d,a,b` | unsigned high 32 bits of `(uint64)A*B` | `Z`, `L=0` |
| `0x23` | `DIV` | `DIV d,a,b` | signed `(int32)A/(int32)B`, trunc toward zero; `B==0 -> 0`; `B==-1 -> 0u-A` | see 3.4 |
| `0x24` | `MOD` | `MOD d,a,b` | signed remainder; `B==0 -> A`; `B==-1 -> 0` | see 3.4 |
| `0x25` | `DIVU` | `DIVU d,a,b` | unsigned divide; `B==0 -> 0` | see 3.4 |
| `0x26` | `MODU` | `MODU d,a,b` | unsigned remainder; `B==0 -> A` | see 3.4 |
| `0x27` | `SAR` | `SAR d,a,imm` | `r[d]=(uint32)((int32)A >> (p&31))` | `Z`, `L=0` |
| `0x28` | `CMPS` | `CMPS a,b` | no write | `Z=A==B`, `L=signed A<B` |
| `0x29` | `ADDI` | `ADDI d,a,imm` | `s2=(uint32)(int32)(int16)imm; s=(uint64)A+s2; r[d]=(uint32)s` | `Z=low==0`, `L=s>>32` |
| `0x2A` | `LDB` | `LDB d,a,imm` | byte at `ad=A+imm`: `(payload[(ad>>2)&M] >> ((ad&3)*8)) & 0xFF` | unchanged |
| `0x2B` | `STB` | `STB d,a,imm` | read-modify-write payload byte at `A+imm`, `n=10` | unchanged |

### 4.2 Memory, control, and link

| `op` | mnemonic | `.nas` form | exact effect (oracle) | flags/PC |
| ---: | --- | --- | --- | --- |
| `0x08` | `LD` | `LD d,a,imm` | `r[d]=payload(mem[(A+imm)&M])` (no head check) | unchanged |
| `0x09` | `ST` | `ST d,a,imm` | `mem[(A+imm)&M]=nan_mkword(r[d],10)` | unchanged |
| `0x0A` | `JMP` | `JMP imm` | `pc=imm` (16-bit) | unchanged |
| `0x0B` | `CALL` | `CALL imm` | `r15=pc_after_fetch; pc=imm` | unchanged |
| `0x0C` | `RET` | `RET` | `pc=r15` | unchanged |
| `0x0D` | `JMPR` | `JMPR a` | `pc=A` | unchanged |
| `0x0E` | bad | - | trap `O` if reached | halt |
| `0x0F` | `NOP` | `NOP` | no effect | unchanged |
| `0x16` | `STW` | `STW d,a,b` | `mem[A&M]=nan_mkword(r[d], B&15)`; note address is `A`, not `A+imm` | unchanged |
| `0x17` | `LDN` | `LDN d,a,imm` | `r[d]=nibble(mem[(A+imm)&M])` if both heads valid, else `0xFFFFFFFF` | unchanged |
| `0x2C` | `CALLR` | `CALLR a` | `r15=pc_after_fetch; pc=A` | unchanged |
| `0x2D` | `BCOPY` | `BCOPY d,a,b` | `dst=r[d]&M`, `src=A&M`, `cnt=B`; if `((dst-src)&M) < cnt` copy backward from last, else forward; raw 8-byte words, each address `&M` | unchanged |
| `0x2E` | `BFILL` | `BFILL d,a,b` | `dst=r[d]`, `cnt=B`, word `nan_mkword(A,10)`; `mem[(dst+i)&M]=word` | unchanged |
| `0x2F` | `NOP` | `NOP` | no effect | unchanged |
| `0x38` | `JMPF` | `JMPF j` | `pc=payload&0xFFFFFF` | unchanged |
| `0x39` | `CALLF` | `CALLF j` | `r15=pc_after_fetch; pc=payload&0xFFFFFF` | unchanged |
| `0xFF` | `HALT` | `HALT` | `halted=1`; oracle leaves `pc=old_pc+1` | halt |

`CALL`/`CALLF`/`CALLR` use `r15` as a normal register; `RET` is predicable
because predication is applied to every op except `BOOL`. There is no
instruction cache or return-stack protection.

### 4.3 Display, input, serial, and device

| `op` | mnemonic | `.nas` form | exact effect (oracle) | flags |
| ---: | --- | --- | --- | --- |
| `0x10` | `VPOKE` | `VPOKE d,a` | graphics: `vram[A]=(uint8)r[d]` if `A<fbtot && A<16MiB`; text: `cells[A]=(uint16)r[d]` if `A<2000`; else ignored | unchanged |
| `0x11` | `VPEEK` | `VPEEK d,a` | graphics: `r[d]=vram[A]` if in range; text: `r[d]=cells[A]` if `A<2000`; else `r[d]` unchanged | unchanged |
| `0x12` | `KEY` | `KEY d` | pop keyboard ring; if empty, rewind `pc` to this op, decrement `steps`, return `NAN_WAIT_KEY` | unchanged |
| `0x13` | `TICK` | `TICK d` | `r[d]=ms`; if `ms==tick_last` and 256 repeats, return `NAN_TIME_WAIT` | unchanged |
| `0x14` | `BSWAPM` | `BSWAPM a,imm` | `mem[(A+imm)&M]=bswap64(word)` | unchanged |
| `0x15` | `PUTC` | `PUTC d` | `nan_ser_putc((uint8)r[d])` | unchanged |
| `0x18` | `DISPQ` | `DISPQ d` | `r[d]=0x1300C800` if graphics, else `0x00031950` | unchanged |
| `0x19` | `DISPSET` | `DISPSET d` | mode switch on `r[d]`: `>=0xFFFF0000` raw keyboard; `>=0x10000` VBE `w=x>>16,h=x&0xFFFF`; low byte `0x13` mode 13h 320x200; else text 80x25 | unchanged |
| `0x1A` | `KEYQ` | `KEYQ d` | pop ring; empty -> `r[d]=0` | unchanged |
| `0x1B` | `NOP` | `NOP` | no effect | unchanged |
| `0x1C..0x1F` | bad | - | trap `O` if reached | halt |
| `0x3A` | `FBINFO` | `FBINFO d` | `r[d]=(fbw<<16)\|fbh` | unchanged |
| `0x3B` | `VSYNC` | `VSYNC` | graphics: `frame++`, return `NAN_VSYNC`; text: no effect | unchanged |
| `0x3C` | `FBCOPY` | `FBCOPY d,a,b` | `fb_copy(count=r[d], dst=A, src=B)` with 16 MiB clamping | unchanged |
| `0x3D` | `FBFILL` | `FBFILL d,a,b` | `fb_fill(count=r[d], start=A, colour=B&255)` | unchanged |
| `0x3E` | `OUTB` | `OUTB d,a` | `nan_port_out(A&0xFFFF, r[d], 1)` | unchanged |
| `0x3F` | `INB` | `INB d,a` | `r[d]=nan_port_in(A&0xFFFF,1)&0xFF` | unchanged |
| `0x40` | `INW` | `INW d,a` | `r[d]=nan_port_in(A&0xFFFF,2)&0xFFFF` | unchanged |
| `0x41` | `OUTW` | `OUTW d,a` | `nan_port_out(A&0xFFFF, r[d]&0xFFFF, 2)` | unchanged |
| `0x42` | `OUTSW` | `OUTSW d,a,b` | `cnt=r[d], idx=B`; for `i<cnt`, output low16 of `mem[idx&M]` payload, `idx++`; port `A&0xFFFF` | unchanged |
| `0x43` | `OUTL` | `OUTL d,a` | `nan_port_out(A&0xFFFF, r[d], 4)` | unchanged |
| `0x44` | `CPUID` | `CPUID d,a,b` | fixed leaf table selected by `A`; `r[d]=reg[B&3]` where regs are EAX,EBX,ECX,EDX (see table below) | unchanged |
| `0x45` | `RDTSC` | `RDTSC d,a` | `r[d]= A==0 ? low32(steps) : high32(steps)` | unchanged |

`CPUID` leaf table (`nan16.c:314-326`):

| Leaf `A` | reg[0] EAX | reg[1] EBX | reg[2] ECX | reg[3] EDX |
| ---: | --- | --- | --- | --- |
| `0` | `0x16` | `0x314E614E` ("NaN1") | `0x4D565F65` ("e_VM") | `0x726F4336` ("6Cor") |
| `1` | `0x00000F10` | 0 | 0 | `1` |
| `0x80000000` | `0x80000004` | 0 | 0 | 0 |
| `0x80000001` | 0 | 0 | 0 | `1 << 29` |
| `0x80000002` | bytes `"NaN16 portable C"` | | | |
| `0x80000003` | bytes `" core (not x86) "` | | | |
| `0x80000004` | 0 | 0 | 0 | 0 |
| other | 0 | 0 | 0 | 0 |

### 4.4 Floating point

The oracle stores IEEE-754 binary32 bit patterns in 32-bit registers via
`memcpy` (`nan16.c:9-11`). Software rules (`nan16.c:13-53`) deliberately
normalize NaNs instead of relying on the host FPU for NaN results.

| `op` | mnemonic | exact effect | flags |
| ---: | --- | --- | --- |
| `0x30` | `FADD` | if A NaN -> `A\|0x00400000`; else if B NaN -> `B\|0x00400000`; else `f32(A)+f32(B)`; if result NaN -> `0xFFC00000` | `k=0` |
| `0x31` | `FSUB` | same NaN rules, `A-B` | `k=0` |
| `0x32` | `FMUL` | same NaN rules, `A*B`; NaN result (0*inf) -> `0xFFC00000` | `k=0` |
| `0x33` | `FDIV` | if `B` magnitude 0: `A` magnitude 0 or NaN -> `0x7FC00000`, else signed infinity; otherwise the FADD/FSUB/FMUL NaN rules, `A/B` | `k=0` |
| `0x34` | `FSQRT` | A NaN or A negative non-zero -> `0x7FC00000`; `-0` -> `-0`; otherwise `sqrtf` | `k=0` |
| `0x35` | `FCMP` | if either NaN -> `k=3`; else `Z=(f32(A)==f32(B))`, `L=(f32(A)<f32(B))` | Z/L |
| `0x36` | `CVTIF` | `r[d]=bits((float)(int32)A)`, round-to-nearest-even | `k=0` |
| `0x37` | `CVTFI` | NaN -> 0; `>=2^31` -> `0x7FFFFFFF`; `<=-2^31` -> `0x80000000`; else `(int32)f` trunc toward zero | `Z=res==0`, `L=0` |
| `0x46` | `FEXP` | NaN -> `A\|0x00400000`; else `expf`; NaN result -> `0x7FC00000` | `k=0` |
| `0x47` | `FTANH` | NaN -> `A\|0x00400000`; else `tanhf`; NaN result -> `0x7FC00000` | `k=0` |
| `0x48` | `FLOG` | NaN -> `A\|0x00400000`; `|A|==0` -> `0xFF800000`; sign bit -> `0x7FC00000`; else `logf`; NaN result -> `0x7FC00000` | `k=0` |

`FADD`/`FSUB`/`FMUL`/`FDIV` first-NaN propagation is A then B; a generated
NaN is `0xFFC00000`. `FDIV` uses `0x7FC00000` for 0/0 or NaN/0. See
`OPS.md:53-60` for the SSE comparison and the ARM warning. The C oracle builds
with `-ffp-contract=off -fno-fast-math`; that is an oracle build assumption,
not a proof.

### 4.5 Reserved / trap space

| `op` | behavior |
| --- | --- |
| `0x49..0xFE` | `op > 0x48` -> trap `O`, shown post-increment PC, unconditional (before predicate) |
| `0x0E`, `0x1C..0x1F` | trap `O` if the predicate passes; predicated-off executions are silent skips |
| any other unlisted `op <= 0x48` | `default` -> trap `O`; currently no such opcode is reachable in the pinned switch |
| `0xFF` | `HALT`, checked before `op > 0x48`; unconditional |

`0x1C`, `0x1D`, `0x1E`, and `0x1F` are four distinct opcodes with the same
trap behavior. `op == 0` (`BOOL`) is never predicated. All other opcodes,
including `RET` and `NOP`, are predicated when `n != 15`.

---

## 5. Literal `.nas` execution: `mth_minsky_test.nas`

### 5.1 Exact source and image pins

- Source: `mth/tests/mth_minsky_test.nas`,
  SHA-256 `173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e`.
- Assembled command:
  `LC_ALL=C gawk -f third_party/nan0s/tools/nmk.awk -v CMD=emit mth/tests/mth_minsky_test.nas`.
- Assembled image: 4,366 words, SHA-256
  `f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77`.
- `CMD=check` on the generated image reports 0 mismatches.
- Word count printed by the assembler: `words 4366`.

### 5.2 Literal label map (assembled, not symbolic)

| Label | Word index | Role |
| --- | ---: | --- |
| `main` | 0 | entry; init and final check |
| `vloop` | 18 | compare 73 tape words against `expected` |
| `run100` | 29 | save link; call `step` 100 times |
| `rloop` | 31 | run100 loop |
| `step` | 36 | one Minsky step |
| `scan` | 47 | table scan loop |
| `mleft` | 67 | move head left |
| `mright` | 69 | move head right |
| `mdone` | 70 | common move tail |
| `step_ret` | 78 | step return |
| `next` | 79 | scan next row |
| `no_trans` | 81 | no match -> halt |
| `puts` | 84 | serial string printer |
| `p1` | 85 | puts outer loop |
| `p2` | 87 | puts byte loop |
| `fail` | 96 | print fail and halt |
| `tbase` | 99 | `.word 4096` |
| `state` | 100 | `.word 0` |
| `head` | 101 | `.word 0` |
| `halt` | 102 | `.word 0` |
| `rlink` | 103 | `.word 0` |
| `table` | 104 | 184 rows x 8 words |
| `expected` | 1576 | 73 expected tape words |
| `s_pass` | 4352 | PASS string + `.word 0` |
| `s_fail` | 4359 | FAIL string + `.word 0` |

Layout:

```text
0..98       code (99 instructions)
99..103     five data cells
104..1575   table (184*8 = 1472 words)
1576..1648  expected (73 words)
1649..4095  zero padding
4096..4223  tape prefix (128 words, all value 2)
4224..4351  tape window (128 words, initial data)
4352..4365  PASS/FAIL strings and terminators
4366        total words
```

The **HEAD certificate** uses abstract control cells
`action_head_addr = 300`, `action_state_addr = 301`,
`action_halt_addr = 302`, `tape_base_addr = 303`,
`fixture_table_base = 304` (`formal/utm/MinskyNaN16RunConcrete.v:30-55` at
HEAD), not the literal `99..104`. The certificate calls this out at
`formal/utm/certificates/nan16-vm/README.md:180-181`. The active worktree
has an uncommitted literalization to `101/100/102/99/104`; that is
**D-10a**, not part of the HEAD pin. A literal refinement must either use the
literal constants or prove an address-relabeling relation. This is **D-10**.

### 5.3 Instruction stream used by the fixture

The fixture uses exactly these 14 mnemonics:

```text
MOVI, ST, LD, CMP, JMP, CALL, RET, ADD, SUB, SHL, SHR, BOOL.8, PUTC, HALT
```

Predicates used: `NE` (9), `EQ` (4), `GE` (1), plus unconditional. The exact
assembled words for the control skeleton are:

```text
000  FFF8_01D00001_F8FF   MOVI r13,1
001  FFF8_01100005_F8FF   MOVI r1,5
002  FFF8_09100064_F8FF   ST r1,r0,100
003  FFF8_011000A6_F8FF   MOVI r1,166
004  FFF8_09100065_F8FF   ST r1,r0,101
005  FFF8_09000066_F8FF   ST r0,r0,102
006  FFF8_0B00001D_F8FF   CALL 29
007  FFF8_08100064_F8FF   LD r1,r0,100
008  FFF8_01200002_F8FF   MOVI r2,2
009  FFF8_07010002_F8FF   CMP r1,r2
010  7FF1_0A000060_F8FF   JMP[NE] 96
...
028  FFF8_FF000000_F8FF   HALT
029  FFF8_09F00067_F8FF   ST r15,r0,103
030  FFF8_01B00064_F8FF   MOVI r11,100
031  FFF8_0B000024_F8FF   CALL 36
032  FFF8_04BB000D_F8FF   SUB r11,r11,r13
033  7FF1_0A00001F_F8FF   JMP[NE] 31
034  FFF8_08F00067_F8FF   LD r15,r0,103
035  FFF8_0C000000_F8FF   RET
...
047  FFF8_07080006_F8FF   CMP r8,r6
048  FFF1_0A000051_F1FF   JMP[GE] 81
049  FFF8_05780003_F8FF   SHL r7,r8,3
050  FFF8_03770005_F8FF   ADD r7,r7,r5
051  FFF8_08970000_F8FF   LD r9,r7,0
...
087  7FF8_00520004_F17F   BOOL.8 r5,r2,r4
088  FFF8_07050000_F8FF   CMP r5,r0
089  FFF1_0C000000_F17F   RET[EQ]
090  FFF8_15500000_F8FF   PUTC r5
091  FFF8_06220008_F8FF   SHR r2,r2,8
```

The `JMP[GE]` word `FFF1_0A000051_F1FF` has near class 1 and far class 1, so
`n = 1<<2 | 1 = 5`; `JMP[NE]` has near class 0 and far class 3, so `n=3`;
`JMP[EQ]` has near class 1 and far class 0, so `n=4`. Data words use `n=10`
(both heads `0x7FF8`); `HALT` uses `n=15` (both heads `0xFFF8`).

### 5.4 What the fixture computes

`main` initializes `r13=1`, state 5, head 166, halt 0, calls `run100`, then
checks `state==2`, `head==166`, and 73 tape words at 4224 against `expected`.
`run100` saves `r15` at `rlink`, calls `step` 100 times, restores `r15`, and
returns. `step` fetches the current tape word at `tbase+head`, scans the 184
table rows in order, and on the first `(state, read)` match writes the tape
word, moves the head, updates state, and sets halt; no match sets halt.
`puts` prints a NUL-terminated byte string with `BOOL.8` and `PUTC` and uses
predicated `RET[EQ]` to exit.

The `puts` path is **not** modeled by the current Coq instruction subset:
`BOOL`, `PUTC`, `SHR`, and predicated `RET` are absent from
`MinskyNaN16VM.Instr` (`MinskyNaN16VM.v:72-83`). A full PASS-path theorem
therefore needs **D-09** and **D-08**, or an explicit scope restriction to
the `run100`/Minsky core.

### 5.5 Oracle observation (not proof)

Running the pinned assembled image on a local build of the **vendored
`nan16.c`** (`05d34f...`) with a 500,000 step budget produces:

```text
rc=NAN_HALTED, pc=29, steps=21025, trace callbacks=18528,
k=2, serial="MTH MINSKY NATIVE PASS"
state cell 100 = 2, head cell 101 = 166
```

Running only word 0 (`nan_run(v, 1)`) produces:

```text
rc=NAN_BUDGET, pc=1, steps=1, k=0, r13=1, serial empty
```

The external runner from section 1.6 reports the same fixture observation:
`[nan_cli] nan-text: 21025 steps, rc=3, pc=29, trap=''` followed by
`MTH MINSKY NATIVE PASS`. These are differential expectations, not theorems.
`pc=29` at halt is the oracle's post-increment convention; see **D-06**.

---

## 6. Coq target model and refinement relation

### 6.1 Coq target model (HEAD certificate)

`formal/utm/MinskyNaN16VM.v` defines:

```coq
Record VM := {
  vm_pc : nat; vm_reg : Reg; vm_mem : Mem;
  vm_zf : bool; vm_lf : bool; vm_halted : bool; vm_link : nat
}.

Inductive Instr :=
| iCMP (a b : nat)
| iJMP (p : preg) (target : nat)
| iSHL (d a imm : nat)
| iADD (d a b : nat)
| iSUB (d a b : nat)
| iLD (d a imm : nat)
| iST (d a imm : nat)
| iMOVI (d imm : nat)
| iCALL (target : nat)
| iRET
| iHALT.
```

`exec_instr` is at `MinskyNaN16VM.v:87-163`; `run_until` is at
`MinskyNaN16VM.v:165-173`. `run_until` stops when `stop pc` or `vm_halted`
is true, before executing the next instruction; fuel 0 returns the VM
unchanged.

The table below describes the **HEAD certificate** model. The active worktree
has uncommitted changes that literalize the address constants; those are
**D-10a** and must not be mixed with this table.

Current model limitations that matter for literal refinement:

| Issue | Coq model | Literal ISA / oracle | Delta |
| --- | --- | --- | --- |
| `ADD` carry | `iADD` sets `lf=false`; `v=A+B` in `nat` | 32-bit wrap; `L=carry` | D-03 |
| `SUB` underflow | `Nat` subtraction truncates at 0 | wraps modulo 2^32 | D-04 |
| `SHL` width | unbounded `Nat.shiftl` | 32-bit result; count `p&31` | D-05 |
| `HALT` PC | `pc` unchanged | `pc` post-incremented | D-06 |
| predicate at `k=3` | `pEQ/pLT/pGE/pLE` differ from bit test | exact bit test | D-07 |
| predication scope | only `iJMP` has a predicate | every op except `BOOL` | D-08 |
| CALL/RET link | `iCALL` writes `vm_link`, not `vm_reg 15`; `iRET` reads `vm_link` | `CALL` writes `r15`; `RET` reads `r15` | D-16 |
| missing ops | no `BOOL`, `PUTC`, `SHR` | used by `puts` | D-09 |
| head gate | no validity gate | trap `!G` | D-11 |
| fetch bounds | `nth_error` miss -> halt | `pc & MASK`, no miss | D-12 |
| memory | total `nat -> nat` | 64-bit words, payload+heads, mask | D-13 |
| addresses (HEAD certificate) | abstract 300..304 | literal 99..104 | D-10 / D-10a |

The current theorem uses `vm_run` / `step_entry`
(`MinskyNaN16Run.v:31-48`) and `step_ok` (`MinskyNaN16Run.v:31-39`), not a
literal `run_until` over an assembled image. That is the gap this contract
targets.

### 6.2 Proposed refinement relation

Define, for a literal machine state `L` (registers, raw memory, `k`, `pc`,
`halted`) and Coq `VM`:

```text
R L vm :=
  vm_pc vm = L.pc                                  (or a documented halt/PC relation)
  /\ forall i < 16, vm_reg vm i = L.r[i] mod 2^32
  /\ forall a < NAN_WORDS,
       vm_mem vm a = payload(L.mem[a])
  /\ vm_zf vm = ((L.k >> 1) & 1 == 1)
  /\ vm_lf vm = (L.k & 1 == 1)
  /\ vm_link vm = L.r[15]
  /\ vm_halted vm = L.halted
```

The memory equality is over **payloads**, because Coq `LD` returns a value
while the oracle `LD` returns only the 32-bit payload (`nan16.c:241`). Head
bytes are represented separately by the word invariant. Coq `ST` writes a
raw value to its abstract memory; the relation must show the oracle writes
`nan_mkword(value, 10)` and that payload projection is the Coq value.

The link relation also needs care: Coq `iCALL` writes `vm_link` but leaves
`vm_reg 15` unchanged, and `iRET` reads `vm_link`; the oracle `CALL` writes
`r15` and `RET` reads `r15`. The fixture additionally saves and restores
`r15` through the `rlink` cell. Either model `r15` as the link register and
change `iCALL`/`iRET`, or exclude `r15` from the register equality in `R`
and prove the fixture's save/restore is a frame no-op. This is **D-16**.
The `forall i < 16` clause above is therefore schematic: do not use it
unchanged for `i = 15` until `vm_link` and `r15` are reconciled.

Choose the halt/PC convention explicitly; do not leave `pc` unconstrained.
The cleanest option is to model the oracle's post-increment in the literal
step and keep `vm_pc` as the next instruction index, then prove that the
Coq `iHALT` case has the same **halted** outcome with a documented PC
offset.

### 6.3 First ISA-level proof obligation

**ISA-OBL-1 (first): `fixture_pc0_decode_and_step`.**

For the pinned assembled image, word 0 is:

```text
0xFFF801D00001F8FF  =  FFF8_01D00001_F8FF  =  MOVI r13,1
```

The first obligation is the conjunction:

1. **Decode:** the literal word decoder maps word 0 to
   `iMOVI 13 1`; the head gate accepts both heads
   (`near = 0xFFF8`, `far = 0xFFF8`, `n = 15`), and the instruction fields
   decode to `op=0x01`, `d=13`, `a=0`, `imm=1`.
2. **One literal step:** from the reset/initial relation
   (`pc=0`, all registers 0, memory loaded from the image, `k=0`,
   `halted=false`, `link=0`), literal execution of word 0 produces
   `pc=1`, `r13=1`, `k=0`, unchanged memory and all other registers.
3. **Coq agreement:** this literal successor equals
   `exec_instr fixture_prog vm0` under `R`, where
   `fixture_prog[0] = iMOVI 13 1`.

In Coq shape:

```coq
Lemma fixture_pc0_decode_and_step :
  decode_word (image_word 0) = Some (iMOVI 13 1) /\
  forall L vm,
    R L vm ->
    L.pc = 0 ->
    R (literal_step image L)
      (exec_instr fixture_prog vm).
```

Here `image` is the full 4,366-word assembled image and `L.pc = 0` selects
word 0; `literal_step` is the independent ISA step, not the C oracle.

The first concrete subgoal is therefore:

```text
decode_word 0xFFF801D00001F8FF = Some (iMOVI 13 1)
```

and its oracle witness is `nan_run(v, 1)` -> `rc=NAN_BUDGET`, `pc=1`,
`r13=1`, `k=0`, `steps=1`.

This is deliberately the base case, not the whole theorem. It forces the
decoder, head-validity, `n=15` predicate, operand extraction, `MOVI`
execution, and PC convention to be fixed before any loop induction.

**Next obligations after ISA-OBL-1:**

| ID | Obligation |
| --- | --- |
| ISA-OBL-2 | Full decoder for words `0..98`: `decode_word (image_word pc) = Some fixture_prog[pc]`, including all branch targets, predicates, and data/table address operands. |
| ISA-OBL-3 | Single-step simulation for every opcode in the fixture subset (`MOVI`, `ST`, `LD`, `CMP`, `JMP`, `CALL`, `RET`, `ADD`, `SUB`, `SHL`, `SHR`, `BOOL`, `PUTC`, `HALT`). |
| ISA-OBL-4 | `run_until`/`run100` induction: 100 calls to `step` preserve the relation and produce the `state=2`, `head=166`, 73-word tape result. |
| ISA-OBL-5 | Address relabeling: literal `99..103` / table `104` versus Coq `300..303` / table `304`, or switch the Coq constants to literal addresses. |
| ISA-OBL-6 | Full PASS path: `puts` with `BOOL`, `PUTC`, `SHR`, `RET[EQ]`, and serial I/O; or an explicit theorem scoped only to `run100`. |

### 6.4 ISA-OBL-2 image-side slices (partial, proved)

The full 4,366-word assembler text is now checked in as
`formal/utm/data/mth_minsky_test.nan` (sha256
`f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77`, 141,409
bytes) together with a word dump
`formal/utm/data/mth_minsky_test.words` (sha256
`43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7`).
`formal/utm/LiteralImageData.v` is the generated Coq `N` transcription, and
`formal/utm/check_nan16_literal_image.py` cross-checks the three
representations; `--assemble` re-runs the pinned HEAD `nmk.awk` and compares
the exact bytes.

`formal/utm/MinskyNaN16LiteralImage.v` proves
`NaNLM.MinskyNaN16LiteralImage.literal_image_matches_fixture`
(`Print Assumptions`: closed).  It covers:

- code slices `[0,84)` and `[96,99)`: `main`, `run100`, the `step` prelude,
  `scan`, `action` (`mleft`/`mright`/`mdone`), `step_ret`, `next`,
  `no_trans`, and `fail`, word for word, including branch targets and
  `NE`/`EQ`/`GE`/`ALWAYS` predicates;
- data cells 99..103: `tbase = 4096`, `state = head = halt = rlink = 0`;
- the payload slice `104..1575` (184x8) equals
  `MinskyNaN16RunConcrete.fixture_table`;
- the tape base cell 99 payload is `fixture_tape_base = 4096`, the 128-word
  prefix at `4096..4223` is all payload 2, and the `.org 4096` padding
  `1649..4095` is all payload 0.

This does **not** close ISA-OBL-2 entirely: the `puts` block `[84,96)`
uses `BOOL.8`, `PUTC`, `SHR`, and a predicated `RET`, which are absent from
`MinskyNaN16VM.Instr`.  ISA-OBL-3..6, the loader/`nan_cli` path, and any
run-refinement statement remain open.  The hash anchors are checked by the
Python gate, not by an in-Coq SHA-256 implementation.

---

## 7. Delta obligations for future core changes

This section is the living part of the contract. Every change to the core,
assembler, fixture, or Coq model must be classified here. A change is not
allowed to silently invalidate a pin or reuse an old theorem.

### 7.1 Change policy

For any proposed change:

1. **Re-pin.** Compute new file SHA-256 values and a new `ISA_REV` /
   `COQ_MODEL_PIN`; do not overwrite the old pin in place. Add a new revision
   row.
2. **Classify.** Mark the change as:
   - **observably equivalent** (same decoded `(op,d,a,imm,n)`, same flags,
     same memory effect, same PC/link behavior),
   - **model extension** (new opcode/predicate/bound the Coq model does not
     yet express), or
   - **breaking** (changes an existing test vector, flag, word layout, mask,
     or halt convention).
3. **Add a delta lemma.** For equivalent changes, prove the old/new decoded
   step relation. For extensions, add the new `Instr` case and its
   `exec_instr` equation. For breaking changes, update the refinement
   relation and all affected gates.
4. **Run the differential gates** in section 8 on the new pin.
5. **Re-run Coq** (`coqc` + `coqchk`) and record `Print Assumptions` if the
   model or theorem changed.
6. **Update this document** and the certificate scope. No immutability claim
   is made.

### 7.2 Open delta register

| ID | Delta | Required action | Status |
| --- | --- | --- | --- |
| **D-01** | Vendored `nan16.c/h/int` bytes differ from `SOURCE.json` and canonical `dcb828...`: `NAN_WORDS 0x400000 -> 0x2000000`, `nan_run`/`done` `uint32 -> uint64`. | Decide: restore canonical bytes, or declare a deliberate fork and update `SOURCE.json` + pins + memory geometry. This is the first delta obligation. | OPEN |
| **D-02** | `OPS.md:6-9` says 4M words / `MASK 0x3FFFFF`; vendored header says 32M words / `0x1FFFFFF`; canonical says 4M; the actual `nan_cli` runner requests 32M. | Pin one `NAN_WORDS`/mask in the ISA contract and prove decoder/bounds against it; record that runner evidence favors 32M. | OPEN |
| **D-03** | Coq `iADD` sets `lf=false`; oracle `ADD` sets `L=carry`. | Extend Coq flags to carry or add an explicit no-carry hypothesis for the fixture. | OPEN |
| **D-04** | Coq `iSUB` uses truncated `Nat` subtraction; oracle wraps modulo 2^32. | Use a 32-bit word model or prove all fixture subtractions are non-underflowing. | OPEN |
| **D-05** | Coq `iSHL` is unbounded `Nat.shiftl`; oracle is 32-bit and uses `p&31`. | Add width/count semantics and prove fixture values fit. | OPEN |
| **D-06** | Oracle `HALT` post-increments `pc`; Coq `iHALT` leaves `pc` unchanged. | Define halt-PC relation or change the literal model; update halt gate. | OPEN |
| **D-07** | Coq `pred_holds` differs from the exact `(n >> (2Z+L)) & 1` at `k=3`. | Replace with the exact bit test or prove `k != 3` for all relevant steps. | OPEN |
| **D-08** | Coq only predicates `iJMP`; oracle predicates every op except `BOOL`; `RET[EQ]` is used by `puts`. | Add a predicate field to every `Instr` or prove the core path never uses predicated non-jump ops. | OPEN |
| **D-09** | Coq `Instr` lacks `BOOL`, `PUTC`, `SHR` (and `puts` support). | Extend `Instr`/`exec_instr` or scope the theorem to `run100` and exclude PASS. | OPEN |
| **D-10** | HEAD Coq control addresses `300..303`, table `304`; literal labels `99..103`, table `104`. | Prove an address relabeling/refinement or replace constants with literal addresses. | OPEN |
| **D-10a** | Active worktree has uncommitted literalization of the Coq chain (`MinskyNaN16Action.v`, `Prelude.v`, `RunClosed.v`, `RunConcrete.v`, `StepOk.v`, `Universality.v`, `check_minsky_nan16_step.py`); not covered by the HEAD certificate. | Compile, `coqc`/`coqchk`, regenerate the certificate, commit, and re-pin; or revert before citing the certificate. | OPEN |
| **D-11** | Oracle checks both head bytes and traps `!G`; Coq has no gate. | Add a well-formed-word invariant for every fetched PC, or model the trap. | OPEN |
| **D-12** | Oracle fetch is `mem[pc & MASK]`; Coq fetch is `nth_error` with miss -> halt. | Prove `pc` stays in the image/list range for the fixture, or model masked fetch. | OPEN |
| **D-13** | Coq memory is total `nat -> nat`; oracle memory is masked 64-bit words with heads. | Define payload projection and address bound; prove `ST`/`LD` relation. | OPEN |
| **D-14** | Oracle `nan_run` is budgeted and can return `NAN_BUDGET`, `NAN_WAIT_KEY`, `NAN_VSYNC`, `NAN_TIME_WAIT`; Coq `run_until` is fuel/stop. | Define the fuel-to-budget relation and exclude wait/vsync for the fixture. | OPEN |
| **D-15** | `nmk.awk`/`nan_load_text` encoding is checked only by source-text gates, not proved. | Prove decoder/encoder correctness for the fixture subset or keep a checked transcription gate with a named trusted boundary. | OPEN |
| **D-16** | Coq `iCALL` writes `vm_link` but not `vm_reg 15`; `iRET` reads `vm_link`; oracle `CALL`/`RET` use `r15`. The fixture saves/restores `r15` through `rlink`. | Choose a link model: equate `vm_link` with `r15` and update `iCALL`/`iRET`, or exclude `r15` from `R` and prove the `rlink` save/restore is a frame no-op. | OPEN |
| **D-17** | The external fixture runner's core `7ed977...` differs from the vendored `05d34f...` and canonical `0ef601...`; only the runner is exercised by `tools/run_nan16_fixtures.py`. | Pin the runner core/CLI with every differential result; classify its semantic differences against the ISA and vendored oracle before treating results as comparable. | OPEN |

A core change that touches any row above must either close the row or add a
new row; do not delete history.

---

## 8. Differential gate plan: C vs Coq vs `.nas` corpus

The gates detect drift. Passing a gate is **not** a refinement proof.

### 8.1 Gate matrix

| Gate | Left side | Right side | Method | Pass criterion |
| --- | --- | --- | --- | --- |
| G0 pin integrity | tracked bytes | documented SHA-256 | `sha256sum` / `git show` | exact match, no stale pin |
| G1 assemble | `.nas` source | `nmk.awk` output | `CMD=emit` | word count, labels, `CMD=check` 0 mismatches |
| G2 source transcription | `.nas` text | Coq mnemonic blocks | `check_minsky_nan16_step.py` | all checks PASS; still only a source gate |
| G3 table transcription | `.nas` table block | canonical table | `check_minsky_nan16_words.py` | 184/184 rows |
| G4 decoder | assembled word | independent `decode_word` | Python/Coq decoder | every `pc` in `0..98` decodes to `fixture_prog[pc]` |
| G5 one-step differential | C `nan_run(v,1)` | Coq `exec_instr` / literal step | per-opcode vectors | same `pc`, regs, payload memory, flags, halted (with documented halt-PC rule) |
| G6 trace differential | C `nan_set_trace` | Coq instrumented `run_until` | trace tuples `(pc,payload,n,k)` | prefix match for the fixture; known wait/vsync excluded |
| G7 full fixture | C oracle | expected marker/state | `nan_cli` or harness | `MTH MINSKY NATIVE PASS`, state=2, head=166, 73-word tape match |
| G8 corpus | all `mth/tests/*.nas` fixtures | C oracle / expected markers | `tools/run_nan16_fixtures.py` | marker present; record step count |
| G9 negative tests | malformed words | decoder/trap | invalid head, `op 0x49`, predicated-off `0x0E`, shift count, div-by-zero, underflow, memory wrap | exact expected trap/skip/wrap |

### 8.2 G0/G1: pin and assemble

If the vendored tree is absent from the sparse checkout, either run
`git sparse-checkout add third_party/nan0s` (a read-only checkout of the
pinned files) or extract the blobs to a temporary directory; do not edit
them.

```sh
cd /data/data/com.termux/files/home/NaNLMind
sha256sum mth/tests/mth_minsky_test.nas
git show HEAD:third_party/nan0s/core/nan16.c | sha256sum
git show HEAD:third_party/nan0s/core/nan16.h | sha256sum
git show HEAD:third_party/nan0s/core/nan16_int.h | sha256sum
git show HEAD:third_party/nan0s/tools/nmk.awk | sha256sum

LC_ALL=C gawk -f third_party/nan0s/tools/nmk.awk \
  -v CMD=emit mth/tests/mth_minsky_test.nas > /tmp/minsky.nan
gawk -f third_party/nan0s/tools/nmk.awk \
  -v CMD=check /tmp/minsky.nan
```

Expected: `words 4366`, `check: 0 mismatches`, image SHA-256
`f78ccb99...`. A label file can be produced with `-v LABELS=...`; the
expected labels are in section 5.2.

### 8.3 G2/G3: existing source gates

```sh
python3 formal/utm/check_minsky_nan16_step.py
python3 formal/utm/check_minsky_nan16_words.py
```

The first gate compares the literal `step`/`run100` mnemonics to the Coq
blocks after an explicit normalization (block-relative targets and HALT
sentinels); it does not check the assembler or encoding. The second checks
184/184 table rows in both Minsky fixtures. Both must PASS, but neither is a
refinement proof.

### 8.4 G4: decoder differential

Build an independent decoder from the ISA table in section 4:

```text
decode_word(w):
  near = w >> 48
  far  = bswap16(w & 0xFFFF)
  n    = (class(near) << 2) | class(far)
  p    = (w >> 16) & 0xFFFFFFFF
  op   = p >> 24
  d    = (p >> 20) & 15
  a    = (p >> 16) & 15
  imm  = p & 0xFFFF
```

For every `pc` in `0..98`, compare `decode_word(image[pc])` against
`fixture_prog[pc]`. The Coq `fixture_prog` should be generated from the
literal image or checked against it; a hand-written list is not sufficient.
Fail closed on an unknown mnemonic, an unmodeled predicate, or a head class
outside the table.

### 8.5 G5: one-step differential

For each opcode used by the fixture, initialize a C VM and a Coq VM to the
same abstract state, execute exactly one instruction, and compare:

- `pc` before/after (apply the documented HALT post-increment rule);
- all 16 registers;
- payload projection of every touched memory word;
- `k` versus `(zf,lf)`;
- `halted`;
- no unintended memory writes (frame).

C one-step adapter is `nan_run(v, 1)`; it returns `NAN_BUDGET` after a normal
instruction, or `NAN_WAIT_KEY` / `NAN_VSYNC` / `NAN_HALTED` for the special
cases. The adapter is not a separate C function and is not a refinement
claim.

Concrete first vector (already observed; re-run after every pin):

```text
initial: pc=0, all r=0, k=0, halted=0, mem=image
execute: word 0 = FFF8_01D00001_F8FF
result:  rc=NAN_BUDGET, pc=1, r13=1, k=0, steps=1, mem unchanged
```

### 8.6 G6: trace differential

Install a C trace callback with `nan_set_trace`; the callback receives
`(ctx, pc, payload, n, k)` at each executed instruction (`nan16.h:27`,
`nan16.c:225`). Instrument the Coq model with the same tuple. For the
fixture, compare the trace prefix and the number of traced instructions; do
not compare predicated-off instructions, because the oracle does not invoke
the trace callback for them.

Known oracle observation for the pinned full run: 18,528 trace callbacks and
21,025 executed fetch attempts. The difference is predicated-off
instructions. Any change to `nan_run` step accounting is **D-14**.

### 8.7 G7/G8: full fixture and corpus

```sh
# C oracle (if the external NaN0S toolchain is present)
python3 tools/run_nan16_fixtures.py --only minsky_table
```

Expected marker: `MTH MINSKY NATIVE PASS`. The C-only corpus gate can run all
fixtures in `tools/run_nan16_fixtures.py`; only `minsky_table` (and the
related Minsky fixtures) have a Coq model counterpart. Corpus PASS is
regression evidence, not a theorem. Record the external runner pin from
section 1.6 with every result; a result from a different `nan_cli`/`nan16.c`
is a different oracle.

For a local oracle build, compile the pinned core with the include files
(`nan16.c`, `nan_dev.c`, `nan_load.c`, `nan_state.c`, `ktab.inc`,
`cp437_utf8.inc`) and load the generated `.nan` with `nan_load_text`; do not
substitute host arithmetic for guest execution.

### 8.8 G9: negative and boundary tests

Required vectors:

| Test | Expected |
| --- | --- |
| fetched word with one invalid head | trap `!G` + shown `pc+1`; `NAN_HALTED` |
| `op = 0x49` | trap `!O` even if predicate bit is 0 |
| `0x0E` with predicate `NEVER` | silent skip, no trap |
| `0x0E` with predicate `ALWAYS` | trap `!O` |
| `SHL/SHR/SAR` with `imm = 32` | count `0` (uses `p&31`) |
| `SAR` of negative value | arithmetic sign fill; document compiler assumption |
| `DIV` `INT32_MIN / -1` | `0u - A` (wraps), no UB |
| `MOD` by 0 | result `A`, `k=3` |
| `SUB` `0 - 1` | `0xFFFFFFFF`, `L=1` |
| `LD` at `pc` near mask boundary | wraps `& MASK`, no fault |
| `.org` backward in `nmk.awk` | assembler rejects |
| `.org` beyond `NAN_WORDS` in loader | load error on next word write |

---

## 9. C oracle inventory (differential use only)

`nan16.c` has **no `nan_step`**. The only fetch/decode/execute function is
`nan_run`, a monolithic loop with a 73-case switch. In the vendored file its
signature is `int nan_run(nan_vm *v, uint64_t max_steps)`; the canonical
snapshot uses `uint32_t max_steps` (see **D-01**). The public API exposes
state accessors and loaders; the device and loader code lives in sibling
files.

### 9.1 Execution core

| Function | Location | Role |
| --- | --- | --- |
| `nan_run` | `nan16.c:207-334` | fetch, gate, decode, predicate, execute, budget/trap/wait |
| `trap` | `nan16.c:158-163` | write `!G`/`!O` text, set `pc`, halt |
| `nan_mkword` | `nan16_int.h:23-26` | build raw word from payload + nibble |
| `nan_near` / `nan_far` | `nan16_int.h:27-28` | extract heads |
| `nan_hvalid` / `nan_hcls` | `nan16_int.h:20-21` | head gate/class |
| `is_nan32`, `f32`, `u32` | `nan16.c:9-11` | float bit transport |
| `fp_bin`, `fp_div`, `fp_sqrt`, `fp_cvtfi`, `fp_unary` | `nan16.c:13-53` | software FP/NaN rules |

### 9.2 Lifecycle, loaders, accessors

| Function | Location | Role |
| --- | --- | --- |
| `nan_create` | `nan16.c:55-64` | allocate VM, memory, VRAM, serial |
| `nan_destroy` | `nan16.c:65-68` | free |
| `nan_reset` | `nan16.c:69-80` | clear memory/regs/flags/display/keyboard |
| `nan_steps` | `nan16.c:83` | read retired-step counter |
| `nan_trap_text` | `nan16.c:84` | read trap string |
| `nan_set_time_ms` | `nan16.c:85` | set `TICK` source |
| `nan_reg` | `nan16.c:86` | read `r[i&15]` |
| `nan_pc` | `nan16.c:87` | read `pc` |
| `nan_word` | `nan16.c:88` | read raw word `mem[i&M]` |
| `nan_set_word` | `nan16.c:89` | write raw word `mem[i&M]` |
| `nan_write_bytes` | `nan16.c:92-105` | inject payload bytes, `n=10` |
| `nan_read_bytes` | `nan16.c:106-117` | extract payload bytes |
| `nan_raw_words_bounds` | `nan16.c:124-132` | validate raw word span/little-endian |
| `nan_write_words_raw` | `nan16.c:133-138` | copy raw words in |
| `nan_read_words_raw` | `nan16.c:139-144` | copy raw words out |
| `nan_set_reg` | `nan16.c:146` | write `r[i&15]` |
| `nan_set_pc` | `nan16.c:147` | write `pc`, clear `halted` |
| `nan_flags` | `nan16.c:148` | read `k` |
| `nan_set_trace` | `nan16.c:149` | install trace callback |
| `nan_dirty` / `nan_frame_counter` | `nan16.c:150-151` | display counters |
| `nan_display_mode` / `nan_display_size` | `nan16.c:152-155` | display queries |
| `nan_text_cell` | `nan16.c:156` | text cell query |

### 9.3 Loaders and device helpers

| Function | Location | Role |
| --- | --- | --- |
| `nan_load_words` | `nan_load.c:8-13` | raw 8-byte words at word 0; resets |
| `nan_load_image` | `nan_load.c:14-18` | floppy image at byte `0x2200`, max 65,536 words |
| `nan_load_error` | `nan_load.c:24` | 1-based load-error line |
| `nan_load_text` | `nan_load.c:25-40` | `.nan` text to raw words; resets |
| `nan_load_auto` | `nan_load.c:41-55` | state/floppy/text/words dispatch |
| `nan_dev_reset` | `nan_dev.c:46-53` | DAC/keyboard/PIT/PCI/ATA reset |
| `nan_ser_putc` | `nan_dev.c:12-16` | serial ring write |
| `nan_ring_pop` / `nan_ring_push` | `nan_dev.c:82-90` | keyboard ring |
| `nan_scancode` / `nan_key_event` / `nan_key_char` | `nan_dev.c:91-117` | IRQ1/cooked input |
| `nan_raw_keyboard` / `nan_speaker_hz` | `nan_dev.c:118-119` | queries |
| `nan_attach_disk_mem` / `_fd` / `nan_detach_disk` | `nan_dev.c:122-124` | ATA backend |
| `nan_port_in` / `nan_port_out` | `nan_dev.c:226-235` | port dispatch + log callbacks |
| `nan_strerror` | `nan_dev.c:236-239` | return-code names |
| `nan_state_size` / `nan_save_state` / `nan_restore_state` | `nan_state.c:74-136` | sparse snapshot; not execution |

`nan_run` caches `uint32_t *r = v->r` and `uint64_t *mem = v->mem` and writes
`v->pc` back only at exit. Registers and memory are modified through those
pointers during the loop. This is important for any oracle harness or VST
model: the VM is not a pure value during execution.

### 9.4 External `nan_cli` path used by the fixture runner

For `mth/tests/mth_minsky_test.nas`, the actual oracle invocation in
`tools/run_nan16_fixtures.py:145-158` is:

```text
tools/run_nan16_fixtures.py
  -> assemble with `nmk.awk -v CMD=emit`
  -> $NAN0S_ROOT/aarch64/android/nan_cli --img <file.nan> --steps N --serial
     -> nan_cli.c:152  nan_create_words(words_for_mb(mem_mb))
     -> nan_cli.c:154  nan_load_auto(...) -> nan_load_text for a .nan image
     -> nan_cli.c:216-221  loop { nan_set_time_ms(...); nan_run(v, slice); }
     -> nan_cli.c:300  report steps, rc, pc, trap
```

There is still no per-instruction `step` function: `nan_run(v, slice)` is the
executor, and `nan_cli` feeds it slices of at most 100,000 steps. The runner
binary and its external core are not part of the vendored `third_party/nan0s`
pin; see section 1.6.

---

## 10. VST / Clightgen feasibility (oracle only)

**Verdict: do not put VST on the critical path.** The target is the Coq ISA
model plus a literal `.nas`/image proof. Verifying `nan16.c` would verify the
oracle, not the implementation, and would not close the literal image gap.
Clightgen may parse the file with shims, but a one-instruction VST contract
has no natural function boundary.

### 10.1 Can `nan16.c` be clightgen'd?

Source-level assessment (Clightgen is not installed in this environment, so
this is not a claim of a successful run):

- The file is mostly C99 and is likely parseable by `clightgen` with the
  right include paths and a 64-bit target configuration.
- **Known parser/translator blockers:**
  - `__builtin_bswap64` at `nan16.c:265` is a GCC builtin. Clight has no
    builtin for it; it needs an external-function axiom or a wrapper/shim.
  - `snprintf` with `%c`/`%04X` in `trap` (`nan16.c:159`) is variadic and
    needs an external spec and format reasoning.
  - `memcpy` bit-punning between `uint32_t` and `float`
    (`nan16.c:10-11`) requires float/word alias reasoning and NaN-payload
    assumptions.
  - `volatile float` operations (`nan16.c:16,31,43`) and `sqrtf`/`expf`/
    `tanhf`/`logf` are host FPU externals; CompCert/VST float semantics do
    not by themselves establish the oracle's NaN-payload normalization.
  - Function pointers `trace` and `portlog` (`nan16.h:27-29`,
    `nan16_int.h:49-50`) require specs for every callback.
  - `calloc`/`free` ownership and the separately allocated `mem`, `vram`,
    `ser` arrays (`nan16.c:55-64`) require a memory-manager invariant.
  - `goto out` plus the `LEAVE` macro (`nan16.c:212`) is supported by
    Clight but complicates the proof.
  - `NAN_WORDS` can be 33M, so a whole-array `data_at` for `v->mem` is
    impractically large; an abstract memory model or a much smaller verified
    configuration is needed.

None of these is a syntax-level impossibility; they are proof-engineering
blockers. A clightgen run is plausible; a **complete** VST proof of
`nan_run` is not a reasonable Layer 0/1 task.

### 10.2 Why there is no natural one-instruction contract

`nan_run` is a loop, not a step function. A one-instruction contract would
have to be a contract on `nan_run(v, 1)` with a loop invariant that covers:

- the fetch/gate/trap branches,
- the `op > 0x48` branch,
- the predicate skip branch,
- all 73 switch cases (including device, FP, and wait/vsync),
- the budget exit and PC write-back.

That is a whole-function contract in disguise. A small contract is possible
only for a **new wrapper** such as:

```c
int nan_step_once(nan_vm *v) { return nan_run(v, 1); }
```

which does not exist in the pinned oracle and would be a code change, not a
refinement of the current file.

### 10.3 Schematic one-instruction VST contract

If a proof-only wrapper is permitted, the contract would have this shape
(illustrative; not compiled or claimed):

```coq
Definition nan_step_once_spec : ident * funspec :=
  DECLARE _nan_step_once
  WITH v : val, pc : Z, k : Z
  PRE [ _v OF tptr Tvoid ]
    PROP (0 <= pc < NAN_WORDS;
          k = 0 \/ k = 1 \/ k = 2 \/ k = 3;
          (* fetched word has valid near/far heads *)
          valid_word (mem_word pc))
    LOCAL (temp _v v)
    SEP (data_at Tsh (tarray tuint 16) (regs_of v) (v . r);
         data_at Tsh (tarray tulong NAN_WORDS) (mem_of v) (v . mem);
         ... vram, cells, device state ...)
  POST [ tint ]
    PROP (rc = NAN_BUDGET \/ rc = NAN_HALTED \/
          rc = NAN_WAIT_KEY \/ rc = NAN_VSYNC \/
          rc = NAN_TIME_WAIT)
    LOCAL (temp ret_temp (Vint (Int.repr rc)))
    SEP (data_at ... updated r ...;
         data_at ... updated mem ...;
         ... frame ...).
```

The POST must split by opcode and by wait/trap outcome. The frame must say
which parts of `nan_vm` are unchanged; the current C code mutates display,
serial, keyboard, ATA, and timing state in addition to `r`/`mem`/`pc`/`k`/
`halted`.

### 10.4 Recommendation

Spend the proof effort on:

1. an independent Coq `decode_word` / `literal_step` for the fixture image;
2. the `exec_instr`/`run_until` refinement (ISA-OBL-1..6);
3. the differential gates in section 8.

If a verified C oracle is later required, refactor a `nan_step` boundary
first (a separate, reviewed change), then verify that boundary and keep the
oracle pin. Do not claim VST coverage of `nan16.c` from a clightgen parse
alone.

---

## 11. Revision and change protocol

- This contract is versioned by `NAN0S-ISA-<n>`; the current pin bundle is
  `ISA_REV-1 = 68d09506...`.
- A revision is **not** a semantic change by itself; the pins and delta
  register are.
- Any changed file in section 1.1 requires:
  - a new pin row (keep old rows);
  - a delta entry in section 7;
  - gate results in section 8;
  - a Coq impact statement (`none`, `model-only`, or `theorem changed`);
  - if the theorem changed, a fresh `coqc` + `coqchk` and `Print
    Assumptions` record.
- Do not edit the vendored oracle to make a gate pass. If the oracle must
  change, declare it, re-pin, and re-run the gates. The C file is not the
  refinement target.
- Do not claim immutability. The only fixed objects here are the historical
  pins and the recorded proof results for those pins.

### Change log

| Revision | Date | Change |
| --- | --- | --- |
| 1 | 2026-11-24 | Initial living contract; literal `.nas` + ISA inventory; C oracle boundary; first ISA obligation; delta register; differential gates; VST assessment. |

---

## 12. Exact references

### Literal fixture and assembler

- `mth/tests/mth_minsky_test.nas` — fixture, labels, table, expected tape.
- `third_party/nan0s/tools/nmk.awk:10-21` — mnemonic/opcode and predicate tables.
- `third_party/nan0s/tools/nmk.awk:180-219` — `.org`, `.str`, `.word`, `LA`, labels.
- `third_party/nan0s/tools/nmk.awk:228-303` — word emission, operand decoding, `MOVI` 16-bit check.
- `third_party/nan0s/tools/nmk.awk:306-314` — `CMD=emit`.
- `third_party/nan0s/core/nan_load.c:25-40` — `.nan` text to raw words.
- `third_party/nan0s/core/nan_load.c:8-18` — raw word/floppy loaders.

### Oracle core

- `third_party/nan0s/core/nan16_int.h:9-28` — mask, word width, heads, classes, `nan_mkword`.
- `third_party/nan0s/core/nan16_int.h:37-52` — `struct nan_vm`.
- `third_party/nan0s/core/nan16.c:9-53` — float/NaN helpers.
- `third_party/nan0s/core/nan16.c:69-80` — reset state.
- `third_party/nan0s/core/nan16.c:92-144` — byte/raw-word transport and bounds.
- `third_party/nan0s/core/nan16.c:158-163` — trap.
- `third_party/nan0s/core/nan16.c:207-334` — `nan_run` fetch/decode/execute.
- `third_party/nan0s/core/nan16.c:214-227` — fetch, gate, PC, predicate, operands.
- `third_party/nan0s/core/nan16.c:228-329` — opcode switch.
- `third_party/nan0s/core/nan16.c:331-333` — budget/PC write-back.
- `third_party/nan0s/core/OPS.md:5-16` — image/word/head rules.
- `third_party/nan0s/core/OPS.md:18-27` — fetch/decode/gate order.
- `third_party/nan0s/core/OPS.md:28-51` — opcode table.
- `third_party/nan0s/core/OPS.md:53-60` — floating-point rules.
- `third_party/nan0s/core/OPS.md:62-96` — display/ports/keyboard.

### Coq target

- `formal/utm/MinskyNaN16VM.v:23-47` — `VM`, `Reg`, `Mem`, `set_reg`.
- `formal/utm/MinskyNaN16VM.v:49-68` — predicates.
- `formal/utm/MinskyNaN16VM.v:72-83` — `Instr`.
- `formal/utm/MinskyNaN16VM.v:87-163` — `exec_instr`.
- `formal/utm/MinskyNaN16VM.v:165-173` — `run_until`.
- `formal/utm/MinskyNaN16VM.v:182-203` — `scan_block` and stop predicate.
- `formal/utm/MinskyNaN16Run.v:13-39` — `entry_ok`, `step_ok`.
- `formal/utm/MinskyNaN16Run.v:41-69` — `vm_run`, `vm_run_refines`.
- `formal/utm/MinskyNaN16RunConcrete.v:30-55` — abstract vs literal addresses, `fixture_table_base = 304`, `fixture_tape_base = 4096`.
- `formal/utm/MinskyNaN16RunConcrete.v:276-311` — address caveat.
- `formal/utm/MinskyNaN16Universality.v:619-649` — final canonical theorem.
- `formal/utm/certificates/nan16-vm/README.md:170-181` — scope and non-claims.
- `formal/utm/certificates/nan16-table/README.md:129-160` — what is still missing for Coq ↔ NaN0S.

### Gates

- `formal/utm/check_minsky_nan16_step.py` — source-text step/run100 gate.
- `formal/utm/check_minsky_nan16_words.py` — 184-row table gate.
- `tools/run_nan16_fixtures.py` — C oracle fixture runner.
- `formal/utm/certificates/nan16-vm/reproduce.sh` — Coq certificate reproduction.

### External runner

- `$NAN0S_ROOT/aarch64/android/tools/nan_cli.c:152` — `nan_create_words`.
- `$NAN0S_ROOT/aarch64/android/tools/nan_cli.c:154` — `nan_load_auto` -> `.nan` text.
- `$NAN0S_ROOT/aarch64/android/tools/nan_cli.c:216-221` — sliced `nan_run`.
- `$NAN0S_ROOT/aarch64/android/tools/nan_cli.c:300` — final steps/rc/pc/trap report.
- `tools/run_nan16_fixtures.py:153-154` — the `--img ... --steps ... --serial` invocation.
