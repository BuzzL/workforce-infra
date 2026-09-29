#!/usr/bin/env bash
# Reads text on stdin and writes it on stdout with what must not appear in a public
# repository's logs, artifacts and comments replaced:
#   12-digit numbers (AWS account IDs)   -> <account-id>
#   the state bucket ($STATE_BUCKET, or anything named workforce-tfstate-*) -> <state-bucket>
#   AWS unique IDs (AROA..., ASIA...; they decode to the account ID) -> <aws-id>
#   email addresses (member account emails) -> <email>
# One script for every job that prints Terraform output, so the passes cannot drift.
set -euo pipefail

args=(
  -E
  -e 's/[0-9]{12}/<account-id>/g'
  -e 's/workforce-tfstate-[a-z0-9-]+/<state-bucket>/g'
  -e 's/(AROA|AIDA|AGPA|AIPA|ANPA|ANVA|APKA|ASCA|ASIA|AKIA)[A-Z0-9]{12,}/<aws-id>/g'
  -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<email>/g'
)
# The exact bucket name, whatever its prefix (bucket names are [a-z0-9-] only).
if [[ -n "${STATE_BUCKET:-}" && "$STATE_BUCKET" =~ ^[a-z0-9.-]+$ ]]; then
  args+=(-e "s/${STATE_BUCKET//./\\.}/<state-bucket>/g")
fi

exec sed "${args[@]}"
