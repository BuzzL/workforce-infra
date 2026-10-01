#!/usr/bin/env bash
# Creates the GitHub Environments <account> and <account>-plan of a member account and sets
# their SECRETS AWS_ROLE_ARN, AWS_ROLE_ID and STATE_BUCKET and the variable AWS_REGION (copied
# from the management environment). A secret is masked everywhere in a public repository's
# logs, a variable is not; the role ID decodes to the account ID, so it is a secret too.
#
#   scripts/set-account-environment-secrets.sh security
#   scripts/set-account-environment-secrets.sh workforce --check   list names only
#
# Run it after the local bootstrap of live/accounts/<account> (docs/ACCOUNT_CI_BASELINES.md):
# the values are read from that stack's Terraform outputs, so it must be initialised with its
# backend.hcl. It needs a gh login that can administer the repository. Values are read into
# memory, validated and passed to `gh` on stdin; nothing is printed except secret names.
# Idempotent: secrets are overwritten, so the end state is always the checked one.
set -euo pipefail

account=${1:-}
case "$account" in
  security | workforce) ;;
  *) echo "usage: $0 <security|workforce> [--check]" >&2; exit 2 ;;
esac
case "${2:-}" in "" | --check) ;; *) echo "usage: $0 <security|workforce> [--check]" >&2; exit 2 ;; esac

repo=BuzzL/workforce-infra
environments="$account ${account}-plan"
cd "$(dirname "$0")/../live/accounts/$account"

names() { # names <secret|variable> <env>: sorted, space separated
  local out
  out=$(gh "$1" list --repo "$repo" --env "$2" --json name -q '[.[].name]|sort|join(" ")') || {
    echo "cannot list ${1}s of $2" >&2
    exit 1
  }
  printf '%s' "$out"
}

list() {
  echo "== $1"
  echo "secrets:   $(names secret "$1")"
  echo "variables: $(names variable "$1")"
}

if [ "${2:-}" = "--check" ]; then
  for e in $environments; do list "$e"; done
  exit 0
fi

read_value() { # read_value <description> <pattern> <command...>: prints the value or fails
  local what=$1 pattern=$2 value
  shift 2
  value=$("$@") || { echo "cannot read $what" >&2; exit 1; }
  [[ $value =~ $pattern ]] || { echo "$what does not have the expected shape" >&2; exit 1; }
  printf '%s' "$value"
}

# Read and validate everything before changing anything.
arn_apply=$(read_value "the apply role ARN" "^arn:aws:iam::[0-9]{12}:role/github-infra-$account\$" terraform output -raw apply_role_arn)
arn_plan=$(read_value "the plan role ARN" "^arn:aws:iam::[0-9]{12}:role/github-infra-$account-plan\$" terraform output -raw plan_role_arn)
id_apply=$(read_value "the apply role ID" '^AROA[A-Z0-9]{12,}$' terraform output -raw apply_role_id)
id_plan=$(read_value "the plan role ID" '^AROA[A-Z0-9]{12,}$' terraform output -raw plan_role_id)
# The bucket and region come from the stack's own backend.hcl (gitignored): a GitHub secret
# cannot be read back.
# shellcheck disable=SC2329 # called through read_value
hcl_value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*\$/\1/p" backend.hcl; }
bucket=$(read_value "the state bucket name in backend.hcl" '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$' hcl_value bucket)
region=$(read_value "the region in backend.hcl" '^[a-z]{2}(-[a-z]+)+-[0-9]$' hcl_value region)

set_secret() { # set_secret <env> <name> <value>
  printf '%s' "$3" | gh secret set "$2" --repo "$repo" --env "$1"
}

set_environment() { # set_environment <env> <role arn> <role id>
  gh api --method PUT "repos/$repo/environments/$1" --silent
  set_secret "$1" AWS_ROLE_ARN "$2"
  set_secret "$1" AWS_ROLE_ID "$3"
  set_secret "$1" STATE_BUCKET "$bucket"
  gh variable set AWS_REGION --repo "$repo" --env "$1" --body "$region"
}

set_environment "$account" "$arn_apply" "$id_apply"
set_environment "${account}-plan" "$arn_plan" "$id_plan"

status=0
for e in $environments; do
  list "$e"
  [ "$(names secret "$e")" = "AWS_ROLE_ARN AWS_ROLE_ID STATE_BUCKET" ] || { echo "unexpected secrets in $e" >&2; status=1; }
done
exit "$status"
