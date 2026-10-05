#!/usr/bin/env bash
# Creates the ExternalId of each environment and writes the variable `agent` into the gitignored
# terraform.tfvars of bootstrap/accounts/test, quality and demo (docs/AGENT_ROLES.md), so that the
# agent roles can be applied locally.
#
#   scripts/set-agent-role-vars.sh             create what is missing, change nothing that exists
#   scripts/set-agent-role-vars.sh --rotate    add a new ExternalId in front, keep the current one
#   scripts/set-agent-role-vars.sh --drop-old  keep only the first ExternalId (after the rotation)
#   scripts/set-agent-role-vars.sh --check     names and counts only, writes nothing
#
# The principal is the agent task role of workforce, read from the Terraform output
# `agent_role_arn` of bootstrap/accounts/workforce (initialised, applied), or from the environment
# variable AGENT_ROLE_ARN. Each ExternalId is 64 random hex characters. The values are written to
# the files only (mode 600) and are never printed or put on a command line. Rotation order
# (docs/ENVIRONMENT_PERMISSIONS.md): --rotate and apply, switch the secret in workforce, --drop-old
# and apply.
set -euo pipefail

mode=${1:-create}
case "$mode" in
  create | --rotate | --drop-old | --check) ;;
  *) echo "usage: $0 [--rotate|--drop-old|--check]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "usage: $0 [--rotate|--drop-old|--check]" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
accounts="test quality demo"
begin='# BEGIN agent (scripts/set-agent-role-vars.sh)'
end='# END agent'

principal=${AGENT_ROLE_ARN:-}
if [ -z "$principal" ] && [ "$mode" != "--check" ]; then
  principal=$(cd "$root/bootstrap/accounts/workforce" && terraform output -raw agent_role_arn) || {
    echo "cannot read agent_role_arn: apply bootstrap/accounts/workforce first, or set AGENT_ROLE_ARN" >&2
    exit 1
  }
fi
if [ -n "$principal" ]; then
  [[ $principal =~ ^arn:aws:iam::([0-9]{12}):role(/[A-Za-z0-9+=,.@_-]+)*/wrkf-[A-Za-z0-9+=,.@_-]+$ ]] || {
    echo "the principal is not the ARN of a wrkf-* role" >&2
    exit 1
  }
  workforce_id=${BASH_REMATCH[1]}
fi

# The ExternalIds of a file, one per line (empty when there is no block).
current_ids() {
  [ -f "$1" ] || return 0
  awk -v b="$begin" -v e="$end" '$0 == b {on = 1} $0 == e {on = 0} on' "$1" |
    grep -E '^[[:space:]]*external_ids' | grep -oE '"[0-9a-f]{64}"' | tr -d '"' || true
}

# Drops the managed block from a file, keeping the rest as it is.
without_block() {
  awk -v b="$begin" -v e="$end" '$0 == b {skip = 1} !skip {print} $0 == e {skip = 0}' "$1"
}

for name in $accounts; do
  dir=$root/bootstrap/accounts/$name
  file=$dir/terraform.tfvars
  [ -d "$dir" ] || { echo "$name: no stack at bootstrap/accounts/$name" >&2; exit 1; }
  ids=$(current_ids "$file")
  count=$(printf '%s' "$ids" | grep -c . || true)

  case "$mode" in
    --check) echo "$name: $count ExternalId(s)"; continue ;;
    create) if [ "$count" -eq 0 ]; then ids=$(openssl rand -hex 32); fi ;;
    --rotate)
      [ "$count" -eq 1 ] || { echo "$name: --rotate needs exactly one ExternalId, found $count" >&2; exit 1; }
      ids=$(printf '%s\n%s' "$(openssl rand -hex 32)" "$ids")
      ;;
    --drop-old)
      [ "$count" -ge 1 ] || { echo "$name: no ExternalId to keep" >&2; exit 1; }
      ids=$(printf '%s' "$ids" | head -n 1)
      ;;
  esac

  list=$(printf '%s\n' "$ids" | awk 'NF {printf "%s\"%s\"", (n++ ? ", " : ""), $0}')
  umask 077
  tmp=$(mktemp "$dir/.tfvars.XXXXXX")
  {
    [ -f "$file" ] && without_block "$file"
    printf '%s\nagent = {\n  principal_arn        = "%s"\n  workforce_account_id = "%s"\n  external_ids         = [%s]\n}\n%s\n' \
      "$begin" "$principal" "$workforce_id" "$list" "$end"
  } > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
  echo "$name: agent set, $(printf '%s\n' "$ids" | grep -c .) ExternalId(s)"
done
