#!/usr/bin/env bash
# Closing a member account takes 90 days and its email stays tied to it, so every
# aws_organizations_account must carry `prevent_destroy = true`. terraform test cannot plan a
# destroy, hence this static check. Usage: check-account-lifecycle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
while IFS= read -r file; do
  if ! awk '
    /resource "aws_organizations_account"/ { inres = 1 }
    inres && /prevent_destroy[[:space:]]*=[[:space:]]*true/ { ok = 1 }
    END { exit ok ? 0 : 1 }' "$file"; then
    echo "$file: aws_organizations_account without prevent_destroy = true" >&2
    status=1
  fi
done < <(grep -rl 'resource "aws_organizations_account"' --include='*.tf' --exclude-dir=.terraform live modules 2>/dev/null)
exit "$status"
