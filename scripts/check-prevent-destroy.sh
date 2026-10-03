#!/usr/bin/env bash
# The damage guard of CI-applied stacks: a resource that must not disappear carries
# `lifecycle { prevent_destroy = true }`, so a plan that would destroy it fails instead of being
# approved by habit. Closing a member account takes 90 days and its email stays tied to it; losing
# an Organizational Unit, a permission set or an account assignment cuts access; a log bucket
# holds the audit trail. terraform test cannot plan a destroy, hence this static check.
#
# Every `resource` block of the types below, in bootstrap/, live/ and modules/, must contain
# `prevent_destroy = true`. Each block is judged on its own: a guarded resource followed by an
# unguarded one in the same file is refused. The roles and the OIDC provider of the account
# baselines are not listed: they are applied locally, and break-glass recovery must be able to
# recreate them. Destroying a listed resource on purpose is a reviewed change that removes the
# line first. Service control policies are not listed: their guard is the staged attachment and
# the review of every change (docs/GUARDRAILS_ROLLOUT.md), and the module that defines them is
# shared by stages that remove an attachment.
#
# Limits, so nobody over-trusts it: it is a net against forgetting the line, not against evasion.
# It reads one resource at a time with a line parser, not HCL: the line must be exactly
# `prevent_destroy = true`, a /* */ comment or a heredoc that holds braces can end a block early
# (the check then fails closed or misses a later line), and the string stripping does not handle
# nested quotes inside an interpolation.
# Usage: check-prevent-destroy.sh [root]   (a test points root at a tree)
set -euo pipefail
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$root"

types="aws_organizations_organizational_unit aws_organizations_account aws_ssoadmin_permission_set aws_ssoadmin_managed_policy_attachment aws_ssoadmin_account_assignment aws_s3_bucket aws_cloudtrail"

status=0
while IFS= read -r file; do
  awk -v types="$types" -v file="$file" '
    BEGIN { n = split(types, t, " "); for (i = 1; i <= n; i++) guard[t[i]] = 1 }
    {
      line = $0
      sub(/#.*/, "", line)              # comments
      sub(/\/\/.*/, "", line)
      if (!inres && match(line, /^[[:space:]]*resource[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"/)) {
        split(line, p, "\"")
        type = p[2]; name = p[4]; start = NR; inres = 1; depth = 0; ok = 0
      }
      if (inres) {
        s = line
        gsub(/"[^"]*"/, "", s)           # strings: braces and text inside them do not count
        if (s ~ /^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true[[:space:]]*$/) ok = 1
        o = gsub(/\{/, "{", s); c = gsub(/\}/, "}", s)
        depth += o - c
        if (depth <= 0 && (o > 0 || c > 0)) {
          if ((type in guard) && !ok) {
            printf "%s:%d: %s.%s must carry lifecycle { prevent_destroy = true }\n", file, start, type, name > "/dev/stderr"
            bad = 1
          }
          inres = 0
        }
      }
    }
    END { exit bad ? 1 : 0 }' "$file" || status=1
done < <(find bootstrap live modules -name '*.tf' -not -path '*/.terraform/*' -not -path '*/tests/*' 2>/dev/null | sort)
exit "$status"
