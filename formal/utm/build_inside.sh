#!/usr/bin/env bash
# Build the mechanized fixed-UTM theorem inside a Coq environment.
# Run through formal/utm/build.sh on the host.
set -eu
ROOT=${ROOT:?ROOT is required}
LIB=${COQ_UNDECIDABILITY:-/data/data/com.termux/files/home/coq-library-undecidability}
JOBS=${JOBS:-2}
OUT=${OUT:-$ROOT/state/benchmarks/mechanized_utm.log}
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1
echo "[coq] $(coqc --version | head -1)"
echo "[lib] $LIB"
if [ ! -f "$LIB/theories/_CoqProject" ]; then
  echo "missing Coq undecidability library at $LIB" >&2
  exit 2
fi
cd "$LIB/theories"
if [ ! -f Makefile.rocq ]; then
  coq_makefile -f _CoqProject -o Makefile.rocq
fi
# Only the fixed-UTM dependency cone.  MetaCoq is not needed for this target.
make -f Makefile.rocq -j"$JOBS" TM/UTM.vo TM/Reductions/KrivineMclosed_HALT_to_HaltUTM.vo
cd "$ROOT"
coqc -Q "$LIB/theories" Undecidability \
  -w -notation-overridden,-stdlib-vector,-notation-incompatible-prefix \
  formal/utm/UTMEquivalence.v
coqc -w -notation-overridden,-stdlib-vector formal/utm/InterpreterRefinement.v
coqc -Q formal/utm NaNLM -w -notation-overridden,-stdlib-vector formal/utm/MinskyTableData.v
coqc -Q formal/utm NaNLM -w -notation-overridden,-stdlib-vector formal/utm/MinskyTable.v
coqchk -Q "$LIB/theories" Undecidability formal/utm/UTMEquivalence.vo
coqchk -Q formal/utm NaNLM formal/utm/InterpreterRefinement.vo
coqchk -Q formal/utm NaNLM formal/utm/MinskyTable.vo
python3 formal/utm/check_minsky_table.py
echo "[coq] theorems checked: UTM_halting_equivalence, utm_run_refines, minsky_trace_100"
