#!/usr/bin/env bash
# Regenerate the raw Coq certificate for lic_lifted_halting_equivalence.
#
# Run from the repository root inside an environment with Coq 8.20 on PATH
# (the Debian proot guest used by the rest of this project works):
#
#   proot-distro login debian -- bash formal/utm/certificates/reproduce.sh
#
# or directly, if coqc/coqchk are on PATH:
#
#   bash formal/utm/certificates/reproduce.sh
set -euo pipefail

cd "$(dirname "$0")/.."   # formal/utm
FLAGS=(-Q . NaNLM -w -notation-overridden,-stdlib-vector)
CERT=certificates/lic_lifted_halting_equivalence

coqc "${FLAGS[@]}" MinskyLeftInfiniteClockRun.v
coqchk -o -Q . NaNLM MinskyLeftInfiniteClockRun.vo > "$CERT.coqchk.txt" 2>&1
coqc "${FLAGS[@]}" certificates/generate_certificate.v

mv "$CERT.statement.txt.out" "$CERT.statement.txt"
mv "$CERT.assumptions.txt.out" "$CERT.assumptions.txt"
mv "$CERT.proofterm.txt.out" "$CERT.proofterm.txt"

awk '/^Checking library: NaNLM.MinskyLeftInfiniteClockRun$/{p=1} p' \
  "$CERT.coqchk.txt" > "$CERT.coqchk.summary.txt"
gzip -9 -c "$CERT.coqchk.txt" > "$CERT.coqchk.txt.gz"
rm -f "$CERT.coqchk.txt"

# Keep the generator's build products out of the source tree.
rm -f certificates/generate_certificate.vo certificates/generate_certificate.glob \
      certificates/generate_certificate.vok certificates/generate_certificate.vos

sha256sum MinskyLeftInfiniteClockRun.v MinskyLeftInfiniteClockRun.vo \
  "$CERT.statement.txt" "$CERT.assumptions.txt" "$CERT.proofterm.txt" \
  "$CERT.coqchk.txt.gz"
echo "Certificate regenerated."
