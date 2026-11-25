#!/usr/bin/env bash
# Regenerate the raw Coq certificate for
# nan16_run_halting_equivalence_canonical.
#
# Run from the repository root inside an environment with Coq 8.20 on PATH
# (the Debian proot guest used by the rest of this project works):
#
#   proot-distro login debian -- bash formal/utm/certificates/nan16-vm/reproduce.sh
#
# or directly, if coqc/coqchk are on PATH:
#
#   bash formal/utm/certificates/nan16-vm/reproduce.sh
set -euo pipefail

cd "$(dirname "$0")/../.."   # formal/utm
FLAGS=(-Q . NaNLM -w -notation-overridden,-stdlib-vector)
CERT=certificates/nan16-vm/nan16_run_halting_equivalence_canonical

# Rebuild the theorem module, then require the kernel checker to pass.
coqc "${FLAGS[@]}" MinskyNaN16Universality.v
coqchk -o -Q . NaNLM MinskyNaN16Universality.vo > "$CERT.coqchk.txt" 2>&1
grep -q '^Modules were successfully checked$' "$CERT.coqchk.txt"
grep -q 'checking cst:NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical' \
  "$CERT.coqchk.txt"

# Redirect the statement, assumptions, and proof term.
coqc "${FLAGS[@]}" certificates/nan16-vm/generate_certificate.v

mv "$CERT.statement.txt.out" "$CERT.statement.txt"
mv "$CERT.assumptions.txt.out" "$CERT.assumptions.txt"
mv "$CERT.proofterm.txt.out" "$CERT.proofterm.txt"
mv certificates/nan16-vm/nan16_source_halt_to_vm.assumptions.txt.out \
   certificates/nan16-vm/nan16_source_halt_to_vm.assumptions.txt
mv certificates/nan16-vm/nan16_vm_halt_to_source.assumptions.txt.out \
   certificates/nan16-vm/nan16_vm_halt_to_source.assumptions.txt
mv certificates/nan16-vm/nan16_run_halting_equivalence.assumptions.txt.out \
   certificates/nan16-vm/nan16_run_halting_equivalence.assumptions.txt

awk '/^Checking library: NaNLM.MinskyNaN16Universality$/{p=1} p' \
  "$CERT.coqchk.txt" > "$CERT.coqchk.summary.txt"
gzip -9 -c "$CERT.coqchk.txt" > "$CERT.coqchk.txt.gz"
rm -f "$CERT.coqchk.txt"

# Keep the generator's build products out of the source tree.
rm -f certificates/nan16-vm/generate_certificate.vo \
      certificates/nan16-vm/generate_certificate.glob \
      certificates/nan16-vm/generate_certificate.vok \
      certificates/nan16-vm/generate_certificate.vos

sha256sum MinskyNaN16Universality.v MinskyNaN16Universality.vo \
  "$CERT.statement.txt" "$CERT.assumptions.txt" "$CERT.proofterm.txt" \
  "$CERT.coqchk.summary.txt" "$CERT.coqchk.txt.gz"
echo "Certificate regenerated."
