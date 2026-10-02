#!/usr/bin/env bash
# Prints the root stacks CI works on as a JSON array. The GitHub Environments are derived
# from the path; an unmapped path fails, so a new stack cannot silently run under the
# wrong environment.
#   ci-stacks.sh apply  (default)  [{stack, environment, apply}] for runs after a merge
#   ci-stacks.sh plan              [{stack, environment}] for plans on pull requests
#
#   stack                 apply environment   applied by CI   plan environment
#   bootstrap             management          no (local)      management-plan
#   live/management       management          yes             management-plan
#   live/accounts/security|workforce  same name  no (local)  <acct>-plan, once <stack>/.ci-enabled exists
#   live/environments/test|qual|demo  same name  yes  none
#
# A stack name is used in JSON and in job names, so it is limited to [a-z0-9/_-], and only
# the environments named below exist: a directory name cannot inject anything or select
# another environment.
set -euo pipefail
cd "$(dirname "$0")/.."

# The deployable environments. Every name is exactly four lowercase letters (^[a-z]{4}$), so
# AWS policies and role-name patterns can match it strictly (docs/ENVIRONMENTS.md). The same
# name is used for the account, the live/environments/<env> stack, the GitHub Environment and
# APP_ENV. management, security and workforce are not environments.
environments="test qual demo"
for e in $environments; do
  [[ $e =~ ^[a-z]{4}$ ]] || { echo "environment name must match ^[a-z]{4}\$: $e" >&2; exit 1; }
done

mode=${1:-apply}
case "$mode" in apply | plan) ;; *) echo "usage: $0 [apply|plan]" >&2; exit 2 ;; esac

out="["
sep=""
while IFS= read -r stack; do
  [ -n "$stack" ] || continue
  plan_env=""
  [[ $stack =~ ^[a-z0-9][a-z0-9/_-]*$ ]] || { echo "invalid stack name: $stack" >&2; exit 1; }
  case "$stack" in
    bootstrap)             env=management apply=false plan_env=management-plan ;;
    live/management)       env=management apply=true plan_env=management-plan ;;
    # Baselines are applied locally through break-glass (the CI role cannot change IAM), so
    # CI only plans them. They join CI when .ci-enabled is committed, after the roles and
    # GitHub Environments exist: until then a plan could only fail.
    live/accounts/security | live/accounts/workforce)
      [ -f "$stack/.ci-enabled" ] || continue
      env=${stack#live/accounts/} apply=false plan_env=${stack#live/accounts/}-plan ;;
    live/environments/*)
      env=${stack#live/environments/}
      case " $environments " in *" $env "*) ;; *) echo "unmapped stack: $stack" >&2; exit 1 ;; esac
      apply=true ;;
    *)                     echo "unmapped stack: $stack" >&2; exit 1 ;;
  esac
  if [ "$mode" = plan ]; then
    [ -n "$plan_env" ] || continue
    out+="$sep{\"stack\":\"$stack\",\"environment\":\"$plan_env\"}"
  else
    out+="$sep{\"stack\":\"$stack\",\"environment\":\"$env\",\"apply\":$apply}"
  fi
  sep=","
done < <(scripts/stacks.sh roots)
echo "$out]"
