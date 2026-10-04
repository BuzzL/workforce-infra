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
