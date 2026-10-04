#!/usr/bin/env bash
# The paths that decide what CI may do (the CI roles and their baselines, the workflow, the gates)
# are named in .github/CODEOWNERS, each with an owner, and every path it names exists. A path
# that is renamed or moved without its line leaves it unowned in practice. CODEOWNERS_FILE and
# CODEOWNERS_ROOT exist for the selftest.
set -euo pipefail
cd "$(dirname "$0")/.."

file=${CODEOWNERS_FILE:-.github/CODEOWNERS}
root=${CODEOWNERS_ROOT:-.}
required=(/bootstrap/ /modules/account-ci-baseline/ /.github/ /scripts/ /Makefile)

[ -f "$file" ] || { echo "check-codeowners.sh: no such file: $file" >&2; exit 2; }
status=0

# pattern owner... for each rule: comments and blank lines dropped.
rules=$(awk '$1 !~ /^#/ && NF > 0' "$file")

while read -r pattern owners; do
  [ -n "$pattern" ] || continue
  if [ -z "$owners" ]; then
    echo "$pattern has no owner" >&2
    status=1
  fi
  [ "$pattern" = "*" ] && continue
  [ -e "$root$pattern" ] || { echo "$pattern does not exist" >&2; status=1; }
done <<< "$rules"

[ "$(awk 'NR == 1 { print $1 }' <<< "$rules")" = "*" ] || { echo "the first rule must be the catch-all *" >&2; status=1; }

for want in "${required[@]}"; do
  awk -v want="$want" '$1 == want { found = 1 } END { exit !found }' <<< "$rules" || { echo "$want is not listed" >&2; status=1; }
done
exit "$status"
