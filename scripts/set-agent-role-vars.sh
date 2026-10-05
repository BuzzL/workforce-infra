#!/usr/bin/env bash
# Creates the ExternalId of each environment and writes the variable `agent` into the gitignored
# terraform.tfvars of bootstrap/accounts/test, quality and demo (docs/AGENT_ROLES.md), so that the
# agent roles can be applied locally.
#
#   scripts/set-agent-role-vars.sh             create what is missing, change nothing that exists (the file is not even rewritten)
#   scripts/set-agent-role-vars.sh --rotate    add a new ExternalId in front, keep the current one
#   scripts/set-agent-role-vars.sh --drop-old  keep only the first ExternalId (after the rotation)
#   scripts/set-agent-role-vars.sh --check     names and counts only, writes nothing
#   scripts/set-agent-role-vars.sh --set-secrets   sets the secret AGENT of the <name>-plan GitHub Environments
#                                              from the files, so that the CI plan of the baseline is a no-op
#                                              (needs gh, authenticated as the maintainer; run it after each apply
#                                              that changes `agent`, and before --drop-old is merged)
#
# The principal is the agent task role of workforce, read from the Terraform output
# `agent_role_arn` of bootstrap/accounts/workforce (initialised, applied), or from the environment
# variable AGENT_ROLE_ARN. Each ExternalId is 64 random hex characters. The values are written to
# the files only (mode 600) and are never printed or put on a command line; the secret is passed
# to gh on stdin. Rotation order
# (docs/ENVIRONMENT_PERMISSIONS.md): --rotate and apply, switch the secret in workforce, --drop-old
# and apply.
set -euo pipefail

mode=${1:-create}
case "$mode" in
  create | --rotate | --drop-old | --check | --set-secrets) ;;
  *) echo "usage: $0 [--rotate|--drop-old|--check|--set-secrets]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "usage: $0 [--rotate|--drop-old|--check|--set-secrets]" >&2; exit 2; }

umask 077
tmp=
trap '[ -z "$tmp" ] || rm -f "$tmp"' EXIT

root=$(cd "$(dirname "$0")/.." && pwd)
accounts="test quality demo"
begin='# BEGIN agent (scripts/set-agent-role-vars.sh)'
end='# END agent'

principal=${AGENT_ROLE_ARN:-}
if [ -z "$principal" ] && [ "$mode" != "--check" ] && [ "$mode" != "--set-secrets" ]; then
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

# The value of the secret AGENT: the block of a file as one line, which Terraform reads from
# TF_VAR_agent as an HCL object.
agent_value() { # agent_value <name> <file>
  local block principal_arn account ids
  block=$(awk -v b="$begin" -v e="$end" '$0 == b {on = 1} $0 == e {on = 0} on' "$2")
  principal_arn=$(printf '%s\n' "$block" | grep -E '^[[:space:]]*principal_arn' | grep -oE '"[^"]+"' | tr -d '"')
  account=$(printf '%s\n' "$block" | grep -E '^[[:space:]]*workforce_account_id' | grep -oE '"[0-9]{12}"' | tr -d '"')
  ids=$(current_ids "$2" | awk 'NF {printf "%s\"%s\"", (n++ ? "," : ""), $0}')
  # The list must close on its line (a hand-edited multi-line list would lose ids), and the account is the principal's.
  printf '%s\n' "$block" | grep -qE '^[[:space:]]*external_ids[[:space:]]*=[[:space:]]*\[.*\][[:space:]]*$' || ids=
  [[ $principal_arn =~ ^arn:aws:iam::([0-9]{12}):role(/[A-Za-z0-9+=,.@_-]+)*/wrkf-[A-Za-z0-9+=,.@_-]+$ && -n $account && -n $ids && $account == "${BASH_REMATCH[1]}" ]] || {
    echo "$1: the agent block of terraform.tfvars is not in the expected shape" >&2
    return 1
  }
  printf '{principal_arn="%s",workforce_account_id="%s",external_ids=[%s]}' "$principal_arn" "$account" "$ids"
}

# Drops the managed block from a file, keeping the rest as it is.
without_block() {
  awk -v b="$begin" -v e="$end" '$0 == b {skip = 1} !skip {print} $0 == e {skip = 0}' "$1"
}

# Refuses a file the markers cannot be trusted on, before anything is written.
check_file() { # check_file <name> <file>
  [ -f "$2" ] || return 0
  if grep -q $'\r' "$2"; then
    echo "$1: terraform.tfvars has CRLF line endings, convert it first" >&2
    return 1
  fi
  local begins ends
  begins=$(grep -cxF "$begin" "$2" || true)
  ends=$(grep -cxF "$end" "$2" || true)
  if [ "$begins" -gt 1 ] || [ "$begins" -ne "$ends" ]; then
    echo "$1: the markers of the agent block are unbalanced, fix terraform.tfvars by hand" >&2
    return 1
  fi
  if without_block "$2" | grep -Eq '^[[:space:]]*agent[[:space:]]*='; then
    echo "$1: terraform.tfvars already sets agent outside the markers, remove it first" >&2
    return 1
  fi
}

# Every value is built and checked before the first call to gh, so that a bad file leaves all
# three secrets as they are.
if [ "$mode" = --set-secrets ]; then
  values=()
  for name in $accounts; do
    file=$root/bootstrap/accounts/$name/terraform.tfvars
    [ -d "$root/bootstrap/accounts/$name" ] || { echo "$name: no stack at bootstrap/accounts/$name" >&2; exit 1; }
    check_file "$name" "$file"
    [ -n "$(current_ids "$file")" ] || { echo "$name: no agent block in terraform.tfvars, run the script without options first" >&2; exit 1; }
    value=$(agent_value "$name" "$file")
    values+=("$value")
  done
  i=0
  for name in $accounts; do
    printf '%s' "${values[$i]}" | gh secret set AGENT --repo BuzzL/workforce-infra --env "$name-plan"
    echo "$name: AGENT set in $name-plan"
    i=$((i + 1))
  done
  exit 0
fi

for name in $accounts; do
  dir=$root/bootstrap/accounts/$name
  file=$dir/terraform.tfvars
  [ -d "$dir" ] || { echo "$name: no stack at bootstrap/accounts/$name" >&2; exit 1; }
  check_file "$name" "$file"
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
  # An existing block keeps its principal: a different one is a decision, not a side effect.
  if [ "$mode" = create ] && [ "$count" -ge 1 ] &&
    ! grep -qF "principal_arn        = \"$principal\"" "$file"; then
    echo "$name: the principal differs from the one in terraform.tfvars, edit it by hand to change it" >&2
    exit 1
  fi
  tmp=$(mktemp "$dir/tmp.XXXXXX.tfvars")
  {
    [ -f "$file" ] && without_block "$file"
    printf '%s\nagent = {\n  principal_arn        = "%s"\n  workforce_account_id = "%s"\n  external_ids         = [%s]\n}\n%s\n' \
      "$begin" "$principal" "$workforce_id" "$list" "$end"
  } > "$tmp"
  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    echo "$name: unchanged, $(printf '%s\n' "$ids" | grep -c .) ExternalId(s)"
    tmp=
    continue
  fi
  mv "$tmp" "$file"
  tmp=
  chmod 600 "$file"
  echo "$name: agent set, $(printf '%s\n' "$ids" | grep -c .) ExternalId(s)"
done
