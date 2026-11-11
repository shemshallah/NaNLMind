#!/usr/bin/env bash
# Safely retire only the inventoried, fully merged branch refs.
set -euo pipefail
mode="${1:---dry-run}"
case "$mode" in --dry-run|--execute) ;; *) echo "Usage: $0 [--dry-run|--execute]" >&2; exit 2;; esac
remote=origin
target=main
branches=(
  docs/runner-ring-authority-20261108
  feat/atomic-runner-ring-authority-20261108
  feat/nannet-koyeb-router-cutover
  feat/single-service-portal-ring-ingress-20261108
  feature/retire-koyeb-config-examples-20261108
  gpt/global-persistence-ntf
  graph-spectral-foundation
  math-catalog-unification
  nan-rawroute-four-tier-addressing
  nannet-canonical-route-hardening
  rss-sparse-capability-contract
)
git rev-parse --is-inside-work-tree >/dev/null
git fetch --prune "$remote" '+refs/heads/*:refs/remotes/origin/*'
head_ref="refs/remotes/${remote}/${target}"
git rev-parse --verify "$head_ref" >/dev/null
for branch in "${branches[@]}"; do
  [[ "$branch" != "$target" ]] || { echo "REFUSED main" >&2; exit 1; }
  branch_ref="refs/remotes/${remote}/${branch}"
  if ! git show-ref --verify --quiet "$branch_ref"; then
    echo "ABSENT $branch"; continue
  fi
  if ! git merge-base --is-ancestor "$branch_ref" "$head_ref"; then
    echo "SKIP unique/unmerged commits: $branch"; continue
  fi
  expected="$(git rev-parse "$branch_ref")"
  # Reject deletion after concurrent branch tip changes (force-with-lease).
  actual="$(git ls-remote --heads "$remote" "refs/heads/$branch" | awk '{print $1}')"
  if [[ -z "$actual" || "$actual" != "$expected" ]]; then
    echo "SKIP moved or absent on remote: $branch"; continue
  fi
  if [[ "$mode" == "--dry-run" ]]; then
    echo "WOULD DELETE merged-only branch: $branch ($expected)"
  else
    git push "$remote" --force-with-lease="refs/heads/${branch}:${expected}" ":refs/heads/$branch"
    echo "DELETED merged-only branch: $branch ($expected)"
  fi
done
