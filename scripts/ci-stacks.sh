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
#   live/environments/test|qa|demo  same name  yes  none
#
# A stack name is used in JSON and in job names, so it is limited to [a-z0-9/_-], and only
# the environments named below exist: a directory name cannot inject anything or select
# another environment.
set -euo pipefail
cd "$(dirname "$0")/.."

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
    live/environments/test | live/environments/qa | live/environments/demo)
      env=${stack#live/environments/} apply=true ;;
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
