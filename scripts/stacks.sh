#!/usr/bin/env bash
# Lists the Terraform directories, one per line: `roots` (bootstrap/ and live/**),
# `modules` (modules/**) or `all`. A directory counts when it directly holds a *.tf or
# *.tf.json file. `tests/` and `.terraform/` directories are skipped: they hold test
# fixtures and provider caches, not stacks.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs() {
  for base in "$@"; do
    [ -d "$base" ] || continue
    find "$base" \( -name .terraform -o -name tests \) -prune -o \
      \( -name '*.tf' -o -name '*.tf.json' \) -print |
      while read -r f; do dirname "$f"; done
  done | sort -u
}

case "${1:-all}" in
  roots)   dirs bootstrap live ;;
  modules) dirs modules ;;
  all)     dirs bootstrap live modules ;;
  *)       echo "usage: $0 [roots|modules|all]" >&2; exit 2 ;;
esac
