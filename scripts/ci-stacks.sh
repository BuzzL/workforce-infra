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
#   bootstrap/accounts/security|workforce  same name  no (local)  <acct>-plan, once <stack>/.ci-enabled exists
#   live/accounts/security                 same name  no (local)  <acct>-plan, once <stack>/.ci-enabled exists
#   live/environments/<name>  same name  yes  none  (accounts of the Environments OU in scripts/environment-keys.tsv)
#
# A stack name is used in JSON and in job names, so it is limited to [a-z0-9/_-], and only
# the environments named below exist: a directory name cannot inject anything or select
# another environment.
set -euo pipefail
cd "$(dirname "$0")/.."

# Names and keys (scripts/environment-keys.tsv, documented in docs/ENVIRONMENTS.md). The name
# is explanatory and used for the account, the live/environments/<name> stack, the GitHub
# Environment and APP_ENV; the key is exactly four lowercase letters, unique, and used in the
# naming conventions of AWS resources so that strict regexps can check them. ENV_KEYS_FILE
# exists for the selftest.
keys_file=${ENV_KEYS_FILE:-scripts/environment-keys.tsv}
environments=""
seen_keys=" "
seen_names=" "
# `|| [ -n "$name" ]` keeps a last row that has no trailing newline; a CR (CRLF file) is stripped.
while IFS=$'\t' read -r name ou key description || [ -n "$name" ]; do
  description=${description%$'\r'}
  case "$name" in "" | \#*) continue ;; esac
  [[ $name =~ ^[a-z]+$ ]] || { echo "name must be lowercase letters: $name" >&2; exit 1; }
  [[ $key =~ ^[a-z]{4}$ ]] || { echo "key of $name must be exactly four lowercase letters (^[a-z]{4}\$): $key" >&2; exit 1; }
  case "$ou" in Management | Development | Environments | Operations) ;; *) echo "unknown OU for $name: $ou" >&2; exit 1 ;; esac
  [[ $description =~ [^[:space:]] ]] || { echo "description of $name is empty" >&2; exit 1; }
  case "$seen_names" in *" $name "*) echo "duplicate name: $name" >&2; exit 1 ;; esac
  seen_names+="$name "
  case "$seen_keys" in *" $key "*) echo "duplicate key: $key" >&2; exit 1 ;; esac
  seen_keys+="$key "
  if [ "$ou" = Environments ]; then environments+="$name "; fi
done < "$keys_file"
[ -n "$environments" ] || { echo "no account in the Environments OU in $keys_file" >&2; exit 1; }

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
    # The baseline of an account (OIDC provider and CI roles) is applied locally, so that the role
    # CI applies with can never change itself: CI only plans it. The account's own stack is still
    # plan-only here. Both join CI when .ci-enabled is committed, after the roles and GitHub
    # Environments exist: until then a plan could only fail.
    bootstrap/accounts/security | bootstrap/accounts/workforce)
      [ -f "$stack/.ci-enabled" ] || continue
      env=${stack#bootstrap/accounts/} apply=false plan_env=${stack#bootstrap/accounts/}-plan ;;
    live/accounts/security)
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
