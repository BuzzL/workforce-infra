#!/usr/bin/env bash
# Sets AWS_ROLE_ARN, AWS_ROLE_ID, STATE_BUCKET, ORGANIZATION_ROOT_ID, ACCOUNT_EMAIL_BASE, BUDGET_ALERT_EMAIL and MEMBER_ACCOUNT_IDS as SECRETS of the
# `management` and `management-plan` GitHub Environments and deletes the variables of the
# same names.
#   AWS_ROLE_ARN   the ARN of the environment's role (from the outputs of bootstrap/)
#   AWS_ROLE_ID    the role's unique ID (from `aws iam get-role`): the credentials action
#                  prints it, and it decodes to the account ID, so it must be masked
#   STATE_BUCKET   the state bucket name
#   ORGANIZATION_ROOT_ID  the Organization root ID (from `aws organizations list-roots`)
#   ACCOUNT_EMAIL_BASE    the base mailbox local@domain of the member accounts, read from the
#                         environment variable of the same name (it cannot be derived)
#   BUDGET_ALERT_EMAIL    the address of the budget alerts, read from the environment variable of
#                         the same name (it is not stored anywhere else)
#   MEMBER_ACCOUNT_IDS    JSON map of the member account IDs, e.g. {"security":"<12 digits>"}, read from
#                         the environment variable of the same name ({} if unset). It is the CI side of
#                         bootstrap's local var.member_account_ids: without it CI would plan the removal
#                         of the member accounts' grants. Keep the two in sync.
#   AUDIT_LOG_BUCKET      optional, read from the environment variable of the same name: the name of
#                         the organization trail's log bucket (docs/AUDIT_LOGGING.md). Unset leaves
#                         audit logging off; it is not removed if it is already set.
# A secret is masked everywhere in a public repository's logs, a variable is not.
#
# Idempotent: running it again converges on the same state. Secrets are overwritten (the
# only way to be sure they match), a variable is deleted only if it exists so that a real
# error is not swallowed, and the end state is checked.
#
# Values are read into memory, validated, and passed to `gh` on stdin. They are not printed
# on success; an error message from terraform, aws or gh may name a resource.
#
#   scripts/set-environment-secrets.sh          set the secrets, delete the old variables
#   scripts/set-environment-secrets.sh --check  list names only, change nothing
#
# Needs an AWS session that can read the state bucket, IAM roles and the Organization
# (`organizations:ListRoots`: the admin SSO profile, not the CI role) (AWS_PROFILE) and a gh
# login that can administer the repository. AWS_REGION stays a variable: it is not sensitive.
set -euo pipefail
cd "$(dirname "$0")/../bootstrap"

repo=BuzzL/workforce-infra
environments="management management-plan"

names() { # names <secret|variable> <env>: sorted, space separated
  local out
  out=$(gh "$1" list --repo "$repo" --env "$2" --json name -q '[.[].name]|sort|join(" ")') || {
    echo "cannot list ${1}s of $2" >&2
    exit 1
  }
  printf '%s' "$out"
}

list() { # list <env>: names only
  echo "== $1"
  echo "secrets:   $(names secret "$1")"
  echo "variables: $(names variable "$1")"
}

case "${1:-}" in
  --check)
    for e in $environments; do list "$e"; done
    exit 0
    ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

read_value() { # read_value <description> <pattern> <command...>: prints the value or fails
  local what=$1 pattern=$2 value
  shift 2
  value=$("$@") || { echo "cannot read $what" >&2; exit 1; }
  [[ $value =~ $pattern ]] || { echo "$what does not have the expected shape" >&2; exit 1; }
  printf '%s' "$value"
}

# Read and validate everything before changing anything.
bucket=$(read_value "the state bucket name" '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$' terraform output -raw state_bucket_name)
arn_management=$(read_value "the management role ARN" '^arn:aws:iam::[0-9]{12}:role/github-infra-management$' terraform output -raw github_infra_management_role_arn)
arn_plan=$(read_value "the plan role ARN" '^arn:aws:iam::[0-9]{12}:role/github-infra-management-plan$' terraform output -raw github_infra_management_plan_role_arn)
id_management=$(read_value "the management role ID" '^AROA[A-Z0-9]{12,}$' aws iam get-role --role-name github-infra-management --query Role.RoleId --output text)
id_plan=$(read_value "the plan role ID" '^AROA[A-Z0-9]{12,}$' aws iam get-role --role-name github-infra-management-plan --query Role.RoleId --output text)

budget_email=$(read_value "BUDGET_ALERT_EMAIL (set it in the environment)" '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' printenv BUDGET_ALERT_EMAIL)
email_base=$(read_value "ACCOUNT_EMAIL_BASE (set it in the environment)" '^[A-Za-z0-9._%-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' printenv ACCOUNT_EMAIL_BASE)

members=${MEMBER_ACCOUNT_IDS:-\{\}}
[[ $members =~ ^\{(\"(security|workforce)\":\"[0-9]{12}\"(,\"(security|workforce)\":\"[0-9]{12}\")*)?\}$ ]] || { echo "MEMBER_ACCOUNT_IDS does not have the expected shape" >&2; exit 1; }

audit_bucket=${AUDIT_LOG_BUCKET:-}
[ -z "$audit_bucket" ] || [[ $audit_bucket =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo "AUDIT_LOG_BUCKET does not have the expected shape" >&2; exit 1; }

root_id=$(read_value "the Organization root ID" '^r-[a-z0-9]{4,32}$' aws organizations list-roots --query 'Roots[0].Id' --output text)

set_secret() { # set_secret <env> <name> <value>
  printf '%s' "$3" | gh secret set "$2" --repo "$repo" --env "$1"
}

set_secret management AWS_ROLE_ARN "$arn_management"
set_secret management AWS_ROLE_ID "$id_management"
set_secret management STATE_BUCKET "$bucket"
set_secret management ORGANIZATION_ROOT_ID "$root_id"
set_secret management ACCOUNT_EMAIL_BASE "$email_base"
set_secret management BUDGET_ALERT_EMAIL "$budget_email"
set_secret management MEMBER_ACCOUNT_IDS "$members"
if [ -n "$audit_bucket" ]; then
  set_secret management AUDIT_LOG_BUCKET "$audit_bucket"
  set_secret management-plan AUDIT_LOG_BUCKET "$audit_bucket"
fi
set_secret management-plan AWS_ROLE_ARN "$arn_plan"
set_secret management-plan AWS_ROLE_ID "$id_plan"
set_secret management-plan STATE_BUCKET "$bucket"
set_secret management-plan ORGANIZATION_ROOT_ID "$root_id"
set_secret management-plan ACCOUNT_EMAIL_BASE "$email_base"
set_secret management-plan BUDGET_ALERT_EMAIL "$budget_email"
set_secret management-plan MEMBER_ACCOUNT_IDS "$members"

# gh lists secrets sorted; the audit log bucket is optional.
expected="ACCOUNT_EMAIL_BASE AWS_ROLE_ARN AWS_ROLE_ID BUDGET_ALERT_EMAIL MEMBER_ACCOUNT_IDS ORGANIZATION_ROOT_ID STATE_BUCKET"
has_audit_bucket() { case " $(names secret "$1") " in *" AUDIT_LOG_BUCKET "*) return 0 ;; *) return 1 ;; esac; }

status=0
for e in $environments; do
  for v in ACCOUNT_EMAIL_BASE AWS_ROLE_ARN AWS_ROLE_ID BUDGET_ALERT_EMAIL MEMBER_ACCOUNT_IDS ORGANIZATION_ROOT_ID STATE_BUCKET; do
    case " $(names variable "$e") " in
      *" $v "*) gh variable delete "$v" --repo "$repo" --env "$e" ;;
    esac
  done
  list "$e"
  want=$expected
  if has_audit_bucket "$e"; then want="ACCOUNT_EMAIL_BASE AUDIT_LOG_BUCKET${expected#ACCOUNT_EMAIL_BASE}"; fi
  [ "$(names secret "$e")" = "$want" ] || { echo "unexpected secrets in $e" >&2; status=1; }
  case " $(names variable "$e") " in
    *" ACCOUNT_EMAIL_BASE "* | *" AWS_ROLE_ARN "* | *" AWS_ROLE_ID "* | *" BUDGET_ALERT_EMAIL "* | *" MEMBER_ACCOUNT_IDS "* | *" ORGANIZATION_ROOT_ID "* | *" STATE_BUCKET "*) echo "a variable of the same name is left in $e" >&2; status=1 ;;
  esac
done
exit "$status"
