#!/usr/bin/env bash
# Creates the GitHub Environments <account> and <account>-plan of a member account and sets
# their SECRETS AWS_ROLE_ARN, AWS_ROLE_ID and STATE_BUCKET and the variable AWS_REGION (copied
# from the stack's backend.hcl). A secret is masked everywhere in a public repository's
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

# The apply environment is the only guard on the apply role (docs/BOOTSTRAP.md, step 0): one
# required reviewer (the maintainer), no admin bypass, only main may deploy. PUT replaces the
# rules, so the same body is always sent and the end state is checked, never assumed.
protect_apply_environment() {
  gh api --method PUT "repos/$repo/environments/$account" --silent --input - <<JSON
{"reviewers":[{"type":"User","id":6116516}],"prevent_self_review":false,"can_admins_bypass":false,
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
JSON
  local policies
  policies=$(gh api "repos/$repo/environments/$account/deployment-branch-policies" --jq '[.branch_policies[].name]|join(" ")')
  if [ -z "$policies" ]; then
    gh api --method POST "repos/$repo/environments/$account/deployment-branch-policies" -f name=main -f type=branch --silent
  elif [ "$policies" != main ]; then
    echo "$account allows branches other than main ($policies): fix it by hand" >&2
    exit 1
  fi
  local state
  state=$(gh api "repos/$repo/environments/$account" --jq '[(.protection_rules[]|select(.type=="required_reviewers")|.reviewers[].reviewer.login), .can_admins_bypass]|join(" ")')
  [ "$state" = "BuzzL false" ] || { echo "$account is not protected as expected (reviewer, no admin bypass)" >&2; exit 1; }
}

set_environment() { # set_environment <env> <role arn> <role id>
  if [ "$1" = "$account" ]; then
    protect_apply_environment
  else
    gh api --method PUT "repos/$repo/environments/$1" --silent # the plan environment: no reviewer, any branch, read-only role
  fi
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
