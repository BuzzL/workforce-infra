#!/usr/bin/env bash
# Keeps the documentation clean. The repository is public and the docs outlive the tickets
# that prompted them, so a doc must stand on its own. Checks, over docs/*.md, README.md,
# CLAUDE.md, CONTRIBUTING.md and SECURITY.md:
#   1. nothing the public must not see: account IDs, ARNs with an account ID, emails (also in
#      *.example files; the reserved example.com/.org/.net domains are fine)
#   2. no planning artifacts: ticket IDs (IAT-nn) or milestone numbers (Mn)
#   3. no unfinished markers: TODO, FIXME, TBD, XXX
#   4. docs/ files are named UPPERCASE_WITH_UNDERSCORES.md
#   5. no `qa` environment (it is `quality`), unless the line also says `quality`
#   6. every docs/*.md is named in CLAUDE.md, so none is orphaned
#   7. every repository path written in backticks (docs/, scripts/, modules/, live/,
#      bootstrap/) exists; paths with a placeholder or a wildcard, live/environments/ and the
#      local files that are never committed (*.tfvars, *.tfstate, backend.hcl) are skipped
# Usage: check-docs.sh [root]   (root defaults to the repository, a test points it at a tree)
set -euo pipefail
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
[ -d "$root/docs" ] || { echo "check-docs.sh: no docs directory in $root" >&2; exit 2; }
cd "$root"

status=0
fail() { echo "$1" >&2; status=1; }

docs=()
for f in docs/*.md README.md CLAUDE.md CONTRIBUTING.md SECURITY.md; do [ -f "$f" ] && docs+=("$f"); done
examples=()
while IFS= read -r f; do examples+=("$f"); done < <(find . -name '*.example' -not -path '*/.terraform/*' -not -path './.git/*' | sed 's|^\./||' | sort)

# scan <description> <extended regexp> <files...>: report every match
scan() {
  local desc=$1 re=$2 out rc=0
  shift 2
  [ "$#" -gt 0 ] || return 0
  out=$(grep -nE -- "$re" "$@") || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "$out" | sed 's/^/  /' >&2
    fail "^ $desc"
  elif [ "$rc" -ne 1 ]; then
    echo "check-docs.sh: grep failed ($rc)" >&2
    status=2
  fi
}

# 1. public repository
public=("${docs[@]}" ${examples[@]+"${examples[@]}"})
scan "a 12-digit AWS account ID" '(^|[^0-9])[0-9]{12}([^0-9]|$)' "${public[@]}"
scan "an AWS account ID written with separators" '(^|[^0-9])[0-9]{4}[- ][0-9]{4}[- ][0-9]{4}([^0-9]|$)' "${public[@]}"
scan "an ARN with an account ID" 'arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]+:' "${public[@]}"
# emails, except the reserved example domains
mail_out=$(grep -nE -- '[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}' "${public[@]}" 2>/dev/null | grep -vE '@(example\.(com|org|net))([^A-Za-z0-9-]|$)' || true)
if [ -n "$mail_out" ]; then
  echo "$mail_out" | sed 's/^/  /' >&2
  fail "^ an email address (only example.com, example.org and example.net are allowed)"
fi

# 2 and 3. planning artifacts and unfinished markers
scan "a ticket ID: state the fact, not the pointer" '\bIAT-[0-9]+\b' "${docs[@]}"
scan "a milestone number: state the fact, not the plan" '\bM[0-9]+\b' "${docs[@]}"
scan "an unfinished marker" '\b(TODO|FIXME|TBD|XXX)\b' "${docs[@]}"

# 4. docs file names
for f in docs/*.md; do
  [ -f "$f" ] || continue
  case $(basename "$f") in
    [A-Z]*.md) ;;
    *) fail "$f: docs file names are UPPERCASE_WITH_UNDERSCORES.md" ;;
  esac
  if ! basename "$f" .md | grep -qE '^[A-Z][A-Z0-9_]*$'; then fail "$f: docs file names are UPPERCASE_WITH_UNDERSCORES.md"; fi
done

# 5. the qa environment
qa=$(grep -nwiE 'qa' "${docs[@]}" | grep -vi 'quality' || true)
if [ -n "$qa" ]; then
  echo "$qa" | sed 's/^/  /' >&2
  fail "^ the environment is named quality (key qual), not qa"
fi

# 6. every doc is indexed in CLAUDE.md
if [ -f CLAUDE.md ]; then
  for f in docs/*.md; do
    [ -f "$f" ] || continue
    grep -qF "\`$f\`" CLAUDE.md || fail "$f: not named in CLAUDE.md (every doc is indexed there)"
  done
fi

# 7. repository paths in backticks exist
for f in "${docs[@]}"; do
  while IFS= read -r p; do
    case $p in *'<'* | *'*'* | *'{'* | live/environments* | *.tfvars | *.tfstate | */backend.hcl) continue ;; esac
    p=${p%[.,:;]}
    [ -e "$p" ] || fail "$f: \`$p\` does not exist"
  done < <(grep -oE '`(docs|scripts|modules|live|bootstrap)/[A-Za-z0-9_./<>*{}-]+`' "$f" | tr -d '`' | sort -u)
done

exit "$status"
