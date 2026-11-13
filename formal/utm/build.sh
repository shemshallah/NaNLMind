#!/bin/sh
# Host-side launcher for the mechanized fixed-UTM theorem.
#
# Coq 8.20 is expected either on PATH or inside the proot Debian guest used by
# this device.  The library is pinned to coq-library-undecidability coq-8.20
# (commit 70dfc56f33a6e4835281044e68aa68279989047e).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LIB=${COQ_UNDECIDABILITY:-$HOME/coq-library-undecidability}
JOBS=${JOBS:-2}
export ROOT LIB JOBS

if command -v coqc >/dev/null 2>&1; then
  exec bash "$ROOT/formal/utm/build_inside.sh"
fi
if command -v proot-distro >/dev/null 2>&1; then
  exec proot-distro login debian -- bash -lc \
    "cd '$ROOT' && ROOT='$ROOT' COQ_UNDECIDABILITY='$LIB' JOBS='$JOBS' bash formal/utm/build_inside.sh"
fi
echo "Coq not found and no proot-distro Debian guest is available" >&2
exit 2
