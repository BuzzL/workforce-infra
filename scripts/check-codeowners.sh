#!/usr/bin/env bash
# The paths that decide what CI may do (the CI roles and their baselines, the workflow, the gates)
# are named in .github/CODEOWNERS, each with an owner, and every plain path it names exists. A path
# that is renamed or moved without its line leaves it unowned in practice. It does not check that a
# later rule leaves the owner of a protected path unchanged (the last match wins on GitHub): the
# approval of the maintainer on any change to this file is the control. CODEOWNERS_FILE and
# CODEOWNERS_ROOT exist for the selftest.
set -euo pipefail
cd "$(dirname "$0")/.."

file=${CODEOWNERS_FILE:-.github/CODEOWNERS}
root=${CODEOWNERS_ROOT:-.}
required=(/bootstrap/ /modules/account-ci-baseline/ /.github/ /scripts/ /Makefile)

[ -f "$file" ] || { echo "check-codeowners.sh: no such file: $file" >&2; exit 2; }
status=0

# pattern owner... for each rule: carriage returns, comments (also after a rule) and blank lines
# dropped.
rules=$(sed -e 's/\r$//' -e 's/[[:space:]]*#.*$//' "$file" | awk 'NF > 0')

while read -r pattern owners; do
  [ -n "$pattern" ] || continue
  if [ -z "$owners" ]; then
    echo "$pattern has no owner" >&2
    status=1
  fi
  for owner in $owners; do
    [[ $owner =~ ^@[^[:space:]]+$ || $owner =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || { echo "$pattern: $owner is not an @user, @org/team or email" >&2; status=1; }
  done
  # Only a plain absolute path can be checked on disk, not a glob or a pattern anywhere in the tree.
  [[ $pattern == /* && $pattern != *[*?[]* ]] || continue
  [ -e "$root$pattern" ] || { echo "$pattern does not exist" >&2; status=1; }
done <<< "$rules"

# House rule, not GitHub's: a catch-all that came later would override every rule above it.
[ "$(awk 'NR == 1 { print $1 }' <<< "$rules")" = "*" ] || { echo "the first rule must be the catch-all *" >&2; status=1; }

for want in "${required[@]}"; do
  awk -v want="$want" '$1 == want { found = 1 } END { exit !found }' <<< "$rules" || { echo "$want is not listed" >&2; status=1; }
done
exit "$status"
