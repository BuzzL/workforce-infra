#!/usr/bin/env bash
# Offline half of the allowed/denied matrix (docs/ENVIRONMENT_PERMISSIONS.md). It checks
# scripts/permission-matrix.tsv against the narrowing rule (demo is inside quality is inside test)
# and against the Allow statements of the role modules: an action allowed in any environment must
# be written in the module, an action denied everywhere must not be. A role widened in the module
# without a matrix row, or a row without the permission, fails here. The live half is
# scripts/run-permission-matrix.sh. MATRIX_FILE and MODULES_DIR exist for the selftest.
set -euo pipefail
cd "$(dirname "$0")/.."

matrix=${MATRIX_FILE:-scripts/permission-matrix.tsv}
modules=${MODULES_DIR:-modules}
status=0
fail() { echo "$1" >&2; status=1; }

[ -f "$matrix" ] || { echo "no matrix: $matrix" >&2; exit 2; }

while IFS=$'\t' read -r role action test quality demo extra; do
  case "$role" in '#'* | '') continue ;; esac
  [ -z "$extra" ] || { fail "$role $action: more than six fields"; continue; }
  file="$modules/$role-role/main.tf"
  [ -f "$file" ] || { fail "$role $action: no module $file"; continue; }
  [[ $action =~ ^[a-z0-9-]+:[A-Za-z0-9]+$ ]] || { fail "$role $action: not a plain action (no wildcard)"; continue; }
  bad=
  for e in "$test" "$quality" "$demo"; do
    [ "$e" = allow ] || [ "$e" = deny ] || bad=1
  done
  [ -z "$bad" ] || { fail "$role $action: effects must be allow or deny"; continue; }
  [ "$demo" != allow ] || [ "$quality" = allow ] || fail "$role $action: allowed in demo but not in quality"
  [ "$quality" != allow ] || [ "$test" = allow ] || fail "$role $action: allowed in quality but not in test"
  written=0
  grep -qF "\"$action\"" "$file" && written=1
  if [ "$test" = allow ] && [ "$written" = 0 ]; then
    fail "$role $action: allowed in the matrix, not in $file"
  elif [ "$test" = deny ] && [ "$written" = 1 ]; then
    fail "$role $action: denied in the matrix, written in $file"
  fi
done < "$matrix"

# Every row has a call in the live runner, or the live job would fail on it.
runner=${RUNNER_FILE:-scripts/run-permission-matrix.sh}
while IFS=$'\t' read -r role action _; do
  case "$role" in '#'* | '') continue ;; esac
  grep -qE "^[[:space:]]+(.*\| )?$action[ )]" "$runner" || fail "$role $action: no call in $runner"
done < "$matrix"

# Every action the modules allow has a row, so a widening cannot go unnoticed.
for role in agent deploy; do
  file="$modules/$role-role/main.tf"
  [ -f "$file" ] || continue
  for action in $(grep -oE '"[a-z0-9-]+:[A-Za-z0-9*]+"' "$file" | tr -d '"' | sort -u); do
    # service:* strings in conditions (iam:PassedToService, cloudformation:RoleArn) are not actions
    awk -F'\t' -v r="$role" -v a="$action" '$1 == r && $2 == a { f = 1 } END { exit !f }' "$matrix" \
      || case "$action" in
        iam:PassedToService | cloudformation:RoleArn | cloudformation:TemplateUrl | sts:* | aws:*) ;;
        *) fail "$role $action: in $file but not in the matrix" ;;
      esac
  done
done

exit "$status"
