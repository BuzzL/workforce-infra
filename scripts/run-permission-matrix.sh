#!/usr/bin/env bash
# Live half of the allowed/denied matrix (docs/ENVIRONMENT_PERMISSIONS.md). Assumes one role of one
# environment and makes, for every row of scripts/permission-matrix.tsv, the call the row names: an
# allowed row must not be refused by IAM, a denied row must be. The calls target resources that do not
# need to exist, because IAM decides before the resource is looked up: a "not found" or "validation"
# error proves the permission, an AccessDenied proves its absence.
#
# Usage: scripts/run-permission-matrix.sh <agent|deploy> <test|quality|demo>
# Environment (all but the first from secrets, none is printed):
#   ROLE_ARN       the role to test
#   EXTERNAL_ID    sent when assuming it (agent role)
#   VIA_ROLE_ARN   a role to assume first, with the ambient credentials (the agent role trusts only the
#                  agent task role of workforce)
#   AWS_REGION     region of the calls
#   ARTIFACT_URL   an S3 URL under the artifact prefix, for the deploy role's CreateStack/CreateChangeSet
# Output names roles, environments and actions only, and goes through scripts/redact.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${MATRIX_REDACTED:-}" ]; then
  MATRIX_REDACTED=1 "$0" "$@" 2>&1 | scripts/redact.sh
  exit "${PIPESTATUS[0]}"
fi

role=${1:?usage: run-permission-matrix.sh <agent|deploy> <test|quality|demo>}
environment=${2:?usage: run-permission-matrix.sh <agent|deploy> <test|quality|demo>}
matrix=${MATRIX_FILE:-scripts/permission-matrix.tsv}
keys=${ENV_KEYS_FILE:-scripts/environment-keys.tsv}
case "$role" in agent | deploy) ;; *) echo "role must be agent or deploy" >&2; exit 2 ;; esac
case "$environment" in test) col=3 ;; quality) col=4 ;; demo) col=5 ;; *) echo "unknown environment: $environment" >&2; exit 2 ;; esac
: "${ROLE_ARN:?ROLE_ARN is required}" "${AWS_REGION:?AWS_REGION is required}"

key=$(awk -F'\t' -v n="$environment" '$1 == n { print $3 }' "$keys")
[ -n "$key" ] || { echo "no key for $environment" >&2; exit 2; }

assume() { # assume <role arn> [extra args]: exports the temporary credentials, prints nothing
  local arn=$1 creds
  shift
  creds=$(aws sts assume-role --role-arn "$arn" --role-session-name "$session" "$@" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text) \
    || { echo "FAIL $role $environment: cannot assume the role"; exit 1; }
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "$creds"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}
session=agent-matrix
[ -z "${VIA_ROLE_ARN:-}" ] || assume "$VIA_ROLE_ARN"
extra=()
[ -z "${EXTERNAL_ID:-}" ] || extra=(--external-id "$EXTERNAL_ID")
assume "$ROLE_ARN" ${extra[@]+"${extra[@]}"}

app=testbed
# "main" is the registered stack of quality and demo: reads and change sets target it. Anything that
# creates, changes or deletes a stack targets "probe", which no role may touch in quality and demo, so
# a role widened by mistake cannot delete the real stack while it is being proven.
base="$key-foundation-$app"
fn=$base-main-function
stack=$base-main-stack
probe_stack=$base-probe-stack
alarm=$base-main-alarm
group=/aws/lambda/$fn
exec_role=${ROLE_ARN/-deploy-role/-exec-role}
tags=(Key=App,Value=$app Key=Environment,Value="$environment")
url=${ARTIFACT_URL:-https://example.invalid/artifact/template.yaml}

# call <action>: the CLI call of one matrix action, against names that do not need to exist.
# Returns 98 for an action that cannot be called on its own, 99 for one with no call.
call() {
  case "$1" in
    lambda:GetFunctionConfiguration) aws lambda get-function-configuration --function-name "$fn" ;;
    lambda:GetAlias) aws lambda get-alias --function-name "$fn" --name live ;;
    lambda:ListVersionsByFunction) aws lambda list-versions-by-function --function-name "$fn" ;;
    lambda:ListAliases) aws lambda list-aliases --function-name "$fn" ;;
    lambda:GetFunction) aws lambda get-function --function-name "$fn" ;;
    lambda:UpdateFunctionCode) aws lambda update-function-code --function-name "$fn" --s3-bucket none --s3-key none ;;
    lambda:CreateFunction) aws lambda create-function --function-name "$fn" --role "$ROLE_ARN" --code S3Bucket=none,S3Key=none ;;
    cloudformation:DescribeStacks) aws cloudformation describe-stacks --stack-name "$stack" ;;
    cloudformation:DescribeStackEvents) aws cloudformation describe-stack-events --stack-name "$stack" ;;
    cloudformation:DescribeChangeSet) aws cloudformation describe-change-set --stack-name "$stack" --change-set-name probe ;;
    cloudformation:GetTemplate) aws cloudformation get-template --stack-name "$stack" ;;
    cloudformation:GetTemplateSummary) aws cloudformation get-template-summary --template-url "$url" ;;
    cloudformation:CreateStack) aws cloudformation create-stack --stack-name "$probe_stack" --template-url "$url" --role-arn "$exec_role" --tags "${tags[@]}" ;;
    cloudformation:DeleteStack) aws cloudformation delete-stack --stack-name "$probe_stack" --role-arn "$exec_role" ;;
    cloudformation:UpdateStack) aws cloudformation update-stack --stack-name "$probe_stack" --template-url "$url" --role-arn "$exec_role" ;;
    cloudformation:CreateChangeSet) aws cloudformation create-change-set --stack-name "$stack" --change-set-name probe --template-url "$url" --role-arn "$exec_role" --tags "${tags[@]}" ;;
    cloudformation:ExecuteChangeSet) aws cloudformation execute-change-set --stack-name "$stack" --change-set-name probe ;;
    cloudformation:DeleteChangeSet) aws cloudformation delete-change-set --stack-name "$stack" --change-set-name probe ;;
    # Not callable on their own: CloudFormation checks them inside the change set and stack calls above.
    cloudformation:TagResource | cloudformation:UntagResource | iam:PassRole) return 98 ;;
    logs:FilterLogEvents) aws logs filter-log-events --log-group-name "$group" ;;
    logs:DescribeLogStreams) aws logs describe-log-streams --log-group-name "$group" ;;
    logs:GetLogEvents) aws logs get-log-events --log-group-name "$group" --log-stream-name probe ;;
    logs:PutLogEvents) aws logs put-log-events --log-group-name "$group" --log-stream-name probe --log-events timestamp=0,message=x ;;
    cloudwatch:DescribeAlarms) aws cloudwatch describe-alarms --alarm-names "$alarm" ;;
    cloudwatch:PutMetricAlarm) aws cloudwatch put-metric-alarm --alarm-name "$alarm" --metric-name m --namespace n --statistic Sum --period 60 --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanThreshold ;;
    iam:CreateRole) aws iam create-role --role-name "$key-foundation-probe-role" --assume-role-policy-document '{}' ;;
    iam:AttachRolePolicy) aws iam attach-role-policy --role-name "$key-foundation-probe-role" --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess ;;
    s3:GetObject) aws s3api get-object --bucket none --key none /dev/null ;;
    sts:AssumeRole) aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name probe ;;
    secretsmanager:GetSecretValue) aws secretsmanager get-secret-value --secret-id probe ;;
    kms:Decrypt) aws kms decrypt --ciphertext-blob fileb:///dev/null ;;
    organizations:DescribeOrganization) aws organizations describe-organization ;;
    account:GetContactInformation) aws account get-contact-information ;;
    *) echo "no call for $1" >&2; return 99 ;;
  esac
}

failed=0
total=0
while IFS=$'\t' read -r r action _; do
  case "$r" in '#'* | '') continue ;; esac
  [ "$r" = "$role" ] || continue
  want=$(awk -F'\t' -v r="$role" -v a="$action" -v c="$col" '$1 == r && $2 == a { print $c }' "$matrix")
  total=$((total + 1))
  rc=0
  out=$(call "$action" 2>&1 < /dev/null) || rc=$?
  if [ "$rc" -eq 98 ]; then
    echo "skip $role $environment $action (proven through the calls that need it)"
    total=$((total - 1))
    continue
  fi
  if [ "$rc" -eq 99 ]; then
    echo "FAIL $role $environment $action: no call defined"
    failed=1
    continue
  fi
  got=allow
  if [ "$rc" -ne 0 ] && grep -qiE 'AccessDenied|not authorized|UnauthorizedOperation' <<< "$out"; then got=deny; fi
  if [ "$got" = "$want" ]; then
    echo "ok   $role $environment $action ($want)"
  else
    echo "FAIL $role $environment $action: wanted $want, got $got"
    failed=1
  fi
done < "$matrix"

[ "$total" -gt 0 ] || { echo "FAIL $role $environment: no rows"; exit 1; }
echo "$role $environment: $total calls, $([ "$failed" = 0 ] && echo passed || echo FAILED)"
exit "$failed"
