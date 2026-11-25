# Literal NaN16 image artifacts (ISA-OBL-2)

These files anchor `formal/utm/MinskyNaN16LiteralImage.v` to the assembled
fixture.  The raw assembler output was not in the repository, so it was
reproduced from the pinned source and the pinned HEAD assembler, then checked
in together with a word-only dump and a generated Coq transcription.

## Files and pins

| File | Role | SHA-256 |
| --- | --- | --- |
| `mth/tests/mth_minsky_test.nas` | fixture source | `173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e` |
| `third_party/nan0s/tools/nmk.awk` (HEAD blob) | assembler | `587116bdffc7715d0dffd6846767dbda76a9d14b55085e9ed8ed08cbdfe1009b` |
| `formal/utm/data/mth_minsky_test.nan` | exact assembler stdout text, 4366 words, 141409 bytes | `f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77` |
| `formal/utm/data/mth_minsky_test.words` | one lowercase 16-hex-digit word per line, 4366 lines | `43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7` |
| `formal/utm/LiteralImageData.v` | generated Coq `N` list, checked equal to `.words` | — (content-addressed by the checker) |

The assembled image pin is the pin recorded in `NAN0S_ISA_SPEC.md` §1.2 and
§5.1.  The `.words` pin is new in this layer; it exists because the Coq
transcription consumes words, not assembler comments.

## Reproduction

From the repository root, with `gawk` available:

```sh
git show HEAD:third_party/nan0s/tools/nmk.awk > /tmp/nmk.awk
LC_ALL=C gawk -f /tmp/nmk.awk -v CMD=emit \
  -v LABELS=/tmp/minsky.labels \
  mth/tests/mth_minsky_test.nas > /tmp/minsky.nan
sha256sum /tmp/minsky.nan
# f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77
# stderr: words 4366
```

Or let the checker do it:

```sh
python3 formal/utm/check_nan16_literal_image.py --assemble --verbose
```

The default checker mode cross-checks the three in-repo representations
without re-running the assembler:

```sh
python3 formal/utm/check_nan16_literal_image.py
```

## Coq

```sh
coqc -Q formal/utm NaNLM formal/utm/LiteralImageData.v
coqc -Q formal/utm NaNLM formal/utm/MinskyNaN16LiteralImage.v
```

`MinskyNaN16LiteralImage.literal_image_matches_fixture` is the ISA-OBL-2
statement.  Its `Print Assumptions` output is closed.

## Remaining gaps

- The decoder covers the `MinskyNaN16VM.Instr` subset only.  The `puts`
  block `[84,96)` uses `BOOL.8`, `PUTC`, `SHR`, and a predicated `RET`,
  which are outside both the Coq instruction type and this decoder.
- The `nan_cli` / `nan16.c` loader and byte-order path are not modelled.
- The hash pins are strings/`N` numerals recorded in Coq and verified by the
  Python checker; there is no in-Coq SHA-256 implementation.
- This is a static image/slice theorem, not a run-refinement theorem for the
  assembled program.
