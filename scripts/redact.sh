#!/usr/bin/env bash
# Reads text on stdin and writes it on stdout with what must not appear in a public
# repository's logs, artifacts and comments replaced:
#   ExternalIds (64 hex characters; also any SHA-256 digest) -> <external-id>
#   12-digit numbers (AWS account IDs)   -> <account-id>
#   the state bucket ($STATE_BUCKET, or anything named workforce-tfstate-*) -> <state-bucket>
#   the audit log bucket ($AUDIT_LOG_BUCKET, or anything named workforce-audit-logs-*) -> <audit-log-bucket>
#   AWS unique IDs (AROA..., ASIA...; they decode to the account ID) -> <aws-id>
#   email addresses (member account emails) -> <email>
#   Identity Center instance and permission set IDs (ssoins-..., ps-...) -> <sso-id>
#   identity store user IDs (UUIDs) -> <uuid>
#   Organization, root and OU IDs (o-xxxxxxxxxx, r-xxxx, ou-xxxx-xxxxxxxx) -> <org-id>
# One script for every job that prints Terraform output, so the passes cannot drift.
set -euo pipefail

args=(
  -E
  # Organization, root and OU IDs. The match consumes its trailing separator, so it is looped
  # (:a ... ta) until no ID is left: two IDs one separator apart are both redacted.
  -e ':a'
  -e 's/(^|[^A-Za-z0-9_-])(ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}|r-[a-z0-9]{4,32}|o-[a-z0-9]{10,32})($|[^A-Za-z0-9_-])/\1<org-id>\3/g'
  -e 'ta'
  # ExternalIds first (docs/AGENT_ROLES.md): a run of 64 hex characters can hold 12 digits.
  -e 's/[0-9a-fA-F]{64}/<external-id>/g'
  # UUIDs next: their last group can be 12 digits.
  -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<uuid>/g'
  -e 's/[0-9]{12}/<account-id>/g'
  -e 's/(ssoins|ps)-[a-z0-9]{8,32}/<sso-id>/g'
  -e 's/workforce-tfstate-[a-z0-9-]+/<state-bucket>/g'
  -e 's/workforce-audit-logs-[a-z0-9-]+/<audit-log-bucket>/g'
  -e 's/(AROA|AIDA|AGPA|AIPA|ANPA|ANVA|APKA|ASCA|ASIA|AKIA)[A-Z0-9]{12,}/<aws-id>/g'
  -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/<email>/g'
)
# Organization IDs. sed has no lookbehind, so the match consumes its separators; the loop
# repeats until nothing is left, so adjacent IDs ("r-ab12 r-cd34") are all replaced.
args+=(
  -e ':orgid'
  -e 't orgid'
)
# The exact bucket name, whatever its prefix (bucket names are [a-z0-9-] only).
if [[ -n "${STATE_BUCKET:-}" && "$STATE_BUCKET" =~ ^[a-z0-9.-]+$ ]]; then
  args+=(-e "s/${STATE_BUCKET//./\\.}/<state-bucket>/g")
fi

if [[ -n "${AUDIT_LOG_BUCKET:-}" && "$AUDIT_LOG_BUCKET" =~ ^[a-z0-9.-]+$ ]]; then
  args+=(-e "s/${AUDIT_LOG_BUCKET//./\\.}/<audit-log-bucket>/g")
fi

exec sed "${args[@]}"
