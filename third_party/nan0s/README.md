# Pinned canonical NaN0S VM snapshot

This directory is a pinned, read-only copy of the canonical NaN0S portable C
core and assembler used by the raw NaN16 field driver. It is the same
dependency and ISA contract used by `NaNLMind_HERMES`, not a second VM.

Source: https://github.com/shemshallah/NaN0S

- `SOURCE.json` records the canonical commit and SHA-256 for every vendored file.
- `core/` is the portable C99 NaN16/NaNVM1 execution core.
- `tools/nmk.awk` is the canonical assembler.
- `LICENSE` is the upstream Apache-2.0 license.

Do not edit these files locally. Update the snapshot from canonical NaN0S and
refresh `SOURCE.json`. The host-facing bridge is `include/nanlm/raw_field.hpp`.
