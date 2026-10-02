#!/usr/bin/env bash
# The repo is public: docs must not carry AWS account IDs, ARNs with an account ID, or email
# addresses. Placeholders such as <account-id> are fine. Usage: check-docs-public.sh [dir]
set -euo pipefail
cd "$(dirname "$0")/.."
dir=${1:-docs}
status=0
scan() { # <description> <extended regexp>
  if grep -rnE --include='*.md' -- "$2" "$dir"; then
    echo "^ $1" >&2
    status=1
  fi
}
scan "a 12-digit AWS account ID" '(^|[^0-9])[0-9]{12}([^0-9]|$)'
scan "an AWS account ID written with separators" '(^|[^0-9])[0-9]{4}[- ][0-9]{4}[- ][0-9]{4}([^0-9]|$)'
scan "an ARN with an account ID" 'arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]+:'
scan "an email address" '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}'
exit "$status"
