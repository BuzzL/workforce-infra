#!/usr/bin/env bash
# Prints the root stacks CI works on as a JSON array. The GitHub Environments are derived
# from the path; an unmapped path fails, so a new stack cannot silently run under the
# wrong environment.
#   ci-stacks.sh apply  (default)  [{stack, environment, apply}] for runs after a merge
#   ci-stacks.sh plan              [{stack, environment}] for plans on pull requests and before an apply
#   ci-stacks.sh gate              reads "<stack> <plan exit code>" lines on stdin, one per stack of `apply`,
#                                  and prints the `apply` entries whose plan has changes (exit code 2), so only
#                                  those wait for an approval. It fails, and prints nothing, on a plan with changes
#                                  in a stack CI does not apply (drift), on any other exit code, and on a missing,
#                                  duplicated or unknown result.
#
#   stack                 apply environment   applied by CI   plan environment
#   bootstrap             management          no (local)      management-plan
#   live/management       management          yes             management-plan
#   bootstrap/accounts/<name>  same name  no (local)  <name>-plan, once <stack>/.ci-enabled exists
#                              (security, workforce and the accounts of the Environments OU in scripts/environment-keys.tsv)
#   live/accounts/security                 same name  yes         <acct>-plan, once <stack>/.ci-enabled exists
#   live/environments/<name>   same name  yes         <name>-plan, once <stack>/.ci-enabled exists
#                              (accounts of the Environments OU in scripts/environment-keys.tsv)
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
case "$mode" in apply | plan | gate) ;; *) echo "usage: $0 [apply|plan|gate]" >&2; exit 2 ;; esac

results=""
if [ "$mode" = gate ]; then results=$(cat); fi
gate_failed=0
known=" "

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
    # CI applies with can never change itself: CI only plans it. The account's own stack is
    # applied by CI, behind the approval of the account's GitHub Environment, with the write
    # permissions its baseline grants. Both join CI when .ci-enabled is committed, after the
    # roles and GitHub Environments exist: until then a plan could only fail.
    bootstrap/accounts/*)
      env=${stack#bootstrap/accounts/}
      case "$env" in security | workforce) ;; *) case " $environments " in *" $env "*) ;; *) echo "unmapped stack: $stack" >&2; exit 1 ;; esac ;; esac
      [ -f "$stack/.ci-enabled" ] || continue
      apply=false plan_env=$env-plan ;;
    live/accounts/security)
      [ -f "$stack/.ci-enabled" ] || continue
      env=${stack#live/accounts/} apply=true plan_env=${stack#live/accounts/}-plan ;;
    live/environments/*)
      env=${stack#live/environments/}
      case " $environments " in *" $env "*) ;; *) echo "unmapped stack: $stack" >&2; exit 1 ;; esac
      # Joins CI with the account's baseline: before its roles and GitHub Environments exist a plan could only fail.
      [ -f "$stack/.ci-enabled" ] || continue
      apply=true plan_env=$env-plan ;;
    *)                     echo "unmapped stack: $stack" >&2; exit 1 ;;
  esac
  if [ "$mode" = gate ]; then
    known+="$stack "
    code=$(awk -v s="$stack" '$1 == s { print $2 }' <<< "$results")
    case "$code" in
      0) continue ;;
      2) if [ "$apply" = true ]; then :; else echo "drift in $stack, which CI does not apply: its plan has changes" >&2; gate_failed=1; continue; fi ;;
      "") echo "no plan result for $stack" >&2; gate_failed=1; continue ;;
      *[!0-9]*) echo "invalid plan result for $stack: $code" >&2; gate_failed=1; continue ;;
      *) echo "the plan of $stack failed (exit code $code)" >&2; gate_failed=1; continue ;;
    esac
    out+="$sep{\"stack\":\"$stack\",\"environment\":\"$env\",\"apply\":$apply}"
  elif [ "$mode" = plan ]; then
    [ -n "$plan_env" ] || continue
    out+="$sep{\"stack\":\"$stack\",\"environment\":\"$plan_env\"}"
  else
    out+="$sep{\"stack\":\"$stack\",\"environment\":\"$env\",\"apply\":$apply}"
  fi
  sep=","
done < <(scripts/stacks.sh roots)
if [ "$mode" = gate ]; then
  # A result for a stack that is not in the CI set, or two for the same stack, means the plan jobs and
  # this script disagree about the stacks: fail rather than guess.
  seen=" "
  while read -r stack _; do
    [ -n "$stack" ] || continue
    case "$known" in *" $stack "*) ;; *) echo "plan result for an unknown stack: $stack" >&2; gate_failed=1 ;; esac
    case "$seen" in *" $stack "*) echo "duplicate plan result for $stack" >&2; gate_failed=1 ;; esac
    seen+="$stack "
  done <<< "$results"
  [ "$gate_failed" = 0 ] || exit 1
fi
echo "$out]"
