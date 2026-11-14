#!/bin/sh
# Dispatch the long-running Coq proof to the nanlm_experimental Actions runner.
set -eu
REPO=${REPO:-shemshallah/nanlm_experimental}
BRANCH=${BRANCH:-master}
JOBS=${JOBS:-2}
gh workflow run mechanized-utm.yml -R "$REPO" --ref "$BRANCH" -f jobs="$JOBS"
echo "dispatched; list runs with:"
echo "  gh run list -R $REPO --workflow mechanized-utm.yml"
echo "  gh run watch -R $REPO"
