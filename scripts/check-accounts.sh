#!/usr/bin/env bash
# The accounts of live/management/accounts.tf and the table of names and keys
# (scripts/environment-keys.tsv) are the same set, each in the same OU. A new account without a
# row has no four-letter key for the naming conventions, and a row without an account is stale.
# terraform test cannot read the table, hence this static check. The key format itself
# (^[a-z]{4}$, unique) is validated by scripts/ci-stacks.sh. ACCOUNTS_FILE and ENV_KEYS_FILE exist
# for the selftest.
set -euo pipefail

accounts_file=${ACCOUNTS_FILE:-live/management/accounts.tf}
keys_file=${ENV_KEYS_FILE:-scripts/environment-keys.tsv}

# `name = "OU"` lines of the `accounts = { ... }` local.
declared=$(awk '
  /^[[:space:]]*accounts[[:space:]]*=[[:space:]]*\{/ { in_block = 1; next }
  in_block && /^[[:space:]]*\}/ { in_block = 0 }
  in_block && match($0, /^[[:space:]]*[a-z]+[[:space:]]*=[[:space:]]*"[A-Za-z]+"[[:space:]]*(#.*)?\r?$/) {
    line = $0
    sub(/[[:space:]]*#.*$/, "", line)
    gsub(/[[:space:]"\r]/, "", line)
    split(line, kv, "=")
    print kv[1] " " kv[2]
  }
' "$accounts_file" | sort)

[ -n "$declared" ] || { echo "no account found in $accounts_file" >&2; exit 1; }

# The management account creates the others: it has a row but is not an account of the stack.
tabled=$(awk -F'\t' '$1 !~ /^(#|$)/ && $1 != "management" { print $1 " " $2 }' "$keys_file" | sort)

if [ "$declared" != "$tabled" ]; then
  echo "accounts.tf and $keys_file disagree (name OU), left is accounts.tf, right is the table:" >&2
  diff <(echo "$declared") <(echo "$tabled") >&2 || true
  exit 1
fi

# The key of an environment account is written in the state bucket policy (bootstrap/state_bucket.tf) and
# in the role names of its baseline stack (bootstrap/accounts/<name>/main.tf). Both must say what the table
# says, or a role would be named differently from the principal the bucket policy admits. ROOT_DIR exists
# for the selftest.
root_dir=${ROOT_DIR:-.}
tabled_keys=$(awk -F'\t' '$1 !~ /^(#|$)/ && $2 == "Environments" { print $1 "=" $3 }' "$keys_file" | sort | tr '\n' ' ')
policy_keys=$(sed -n 's/^[[:space:]]*environment_keys[[:space:]]*=[[:space:]]*{\(.*\)}[[:space:]]*$/\1/p' "$root_dir/bootstrap/state_bucket.tf" | sed 's/"//g; s/,/ /g; s/=/ = /g' | awk '{ for (i = 1; i <= NF; i += 3) print $i "=" $(i + 2) }' | sort | tr '\n' ' ')
[ -n "$policy_keys" ] || { echo "environment_keys not found on one line in $root_dir/bootstrap/state_bucket.tf" >&2; exit 1; }
if [ "$tabled_keys" != "$policy_keys" ]; then
  echo "environment_keys in bootstrap/state_bucket.tf and the Environments rows of $keys_file disagree: '$policy_keys' vs '$tabled_keys'" >&2
  exit 1
fi
while IFS=$'\t' read -r name ou key _; do
  [ "$ou" = Environments ] || continue
  main="$root_dir/bootstrap/accounts/$name/main.tf"
  [ -f "$main" ] || continue
  grep -Eq "^[[:space:]]*apply_role_name[[:space:]]*=[[:space:]]*\"$key-foundation-infra-role\"" "$main" || { echo "$main must name the role $key-foundation-infra-role as apply_role_name (key of $name in $keys_file)" >&2; exit 1; }
  grep -Eq "^[[:space:]]*plan_role_name[[:space:]]*=[[:space:]]*\"$key-foundation-infra-plan-role\"" "$main" || { echo "$main must name the role $key-foundation-infra-plan-role as plan_role_name (key of $name in $keys_file)" >&2; exit 1; }
  grep -Eq "^[[:space:]]*role_path[[:space:]]*=[[:space:]]*\"/platform/\"" "$main" || { echo "$main must set role_path to /platform/" >&2; exit 1; }
  live="$root_dir/live/environments/$name"
  [ -d "$live" ] || continue
  grep -Eq "^[[:space:]]*key[[:space:]]*=[[:space:]]*\"$key\"" "$live/main.tf" || { echo "$live/main.tf must set key to $key (key of $name in $keys_file)" >&2; exit 1; }
  grep -Eq "^key[[:space:]]*=[[:space:]]*\"live/environments/$name/terraform.tfstate\"" "$live/backend.hcl.example" || { echo "$live/backend.hcl.example must hold the key live/environments/$name/terraform.tfstate" >&2; exit 1; }
done < <(grep -v '^#' "$keys_file")
