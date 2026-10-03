#!/usr/bin/env bash
# Resources whose loss is unrecoverable or a lockout must carry `lifecycle { prevent_destroy =
# true }`. terraform test cannot plan a destroy, so this is a static check: for each guarded
# type, every resource block of that type (scoped by its own braces) must set prevent_destroy.
#   aws_organizations_account                 closing a member account takes 90 days, email stays tied
#   aws_s3_bucket                             the state and audit-log buckets hold history
#   aws_ssoadmin_permission_set               losing a set removes the maintainer's access
#   aws_ssoadmin_managed_policy_attachment    detaching the policy strips the set's permissions
#   aws_ssoadmin_account_assignment           deleting it locks the maintainer out of the account
# Curated on purpose: a new type joins the guard by being added here and to its module, never by
# a blanket rule that would force prevent_destroy onto every role and bucket in the repo.
# Usage: check-prevent-destroy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

types="aws_organizations_account aws_s3_bucket aws_ssoadmin_permission_set aws_ssoadmin_account_assignment aws_ssoadmin_managed_policy_attachment"
alternation=${types// /|}

status=0
while IFS= read -r file; do
  # Per-block scan: a file can hold several guarded resources, each scored on its own braces,
  # so a guard on one block never covers a sibling that is missing it.
  awk -v types="$types" '
    function count(ch, s,   c, i) { c = 0; for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == ch) c++; return c }
    BEGIN { n = split(types, t, " "); for (i = 1; i <= n; i++) guarded[t[i]] = 1 }
    {
      # Drop double-quoted strings before counting braces, so a brace inside a string value
      # cannot open or close a block. The guarded types carry no jsonencode, so this is enough.
      stripped = $0
      gsub(/"[^"]*"/, "", stripped)
    }
    !inres && $1 == "resource" {
      rtype = $2; gsub(/"/, "", rtype)
      rname = $3; gsub(/"/, "", rname)
      if (rtype in guarded) { inres = 1; depth = 0; open = 0; ok = 0; curtype = rtype; curname = rname }
    }
    inres {
      if ($0 ~ /prevent_destroy[[:space:]]*=[[:space:]]*true/) ok = 1
      depth += count("{", stripped) - count("}", stripped)
      if (depth > 0) open = 1
      if (open && depth <= 0) {
        if (!ok) { print FILENAME ": " curtype "." curname " without prevent_destroy = true"; bad = 1 }
        inres = 0
      }
    }
    END { exit bad ? 1 : 0 }
  ' "$file" || status=1
done < <(grep -rlE "resource \"($alternation)\"" --include='*.tf' --exclude-dir=.terraform bootstrap live modules 2>/dev/null)
exit "$status"
