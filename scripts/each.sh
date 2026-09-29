#!/usr/bin/env bash
# Runs one gate in every Terraform directory listed by stacks.sh. Lives in a script, not
# in Makefile recipes, so it stops on the first error whatever the Make version (macOS
# ships Make 3.81, which ignores .SHELLFLAGS).
set -euo pipefail
cd "$(dirname "$0")/.."

gate=${1:?usage: each.sh validate|lint|test|versions|dependabot}
dirs=$(scripts/stacks.sh all)
if [ -z "$dirs" ]; then
  echo "no Terraform directories, nothing to check for $gate"
  exit 0
fi

has_tests() { compgen -G "$1/*.tftest.hcl" >/dev/null || compgen -G "$1/tests/*.tftest.hcl" >/dev/null; }

# Convention: required_version >= 1.9, and the AWS provider pinned to ~> 6. This is a
# text match on *.tf files, so keep the constraints on one line as in the docs.
check_versions() {
  local d=$1 rc=0
  if ! grep -qE 'required_version[[:space:]]*=[[:space:]]*">=[[:space:]]*1\.(9|[1-9][0-9]+)' "$d"/*.tf 2>/dev/null; then
    echo "$d: required_version must be \">= 1.9\" (or higher) in a .tf file"
    rc=1
  fi
  if grep -qE 'hashicorp/aws' "$d"/*.tf 2>/dev/null &&
    ! grep -qE 'version[[:space:]]*=[[:space:]]*"~>[[:space:]]*6(\.[0-9]+)*"' "$d"/*.tf; then
    echo "$d: the hashicorp/aws provider must be pinned to \"~> 6\""
    rc=1
  fi
  return "$rc"
}

# Dependabot fails on missing directories, so each stack that declares providers is added
# to its terraform block by the PR that creates it. This makes forgetting that fail.
check_dependabot() {
  local d=$1 pat
  grep -qs required_providers "$d"/*.tf || return 0
  while read -r pat; do
    # shellcheck disable=SC2053
    [[ "/$d" == $pat ]] && return 0
  done < <(awk '
    /package-ecosystem:/ { t = ($0 ~ /terraform/) ; next }
    t && /^[[:space:]]*(-|directory:)[[:space:]]*\// { sub(/^[[:space:]]*(- |directory: )[[:space:]]*/, ""); print }
  ' .github/dependabot.yml)
  echo "$d: declares providers but is not in the terraform block of .github/dependabot.yml"
  return 1
}

case "$gate" in
  lint) tflint --init ;;
esac

# validate and test initialise into a throwaway data dir, so they ignore (and leave alone)
# a backend cached by a local `terraform init` in the same directory.
data_dir=$(mktemp -d)
trap 'rm -rf "$data_dir"' EXIT
export TF_DATA_DIR="$data_dir"

status=0
while IFS= read -r d; do
  rm -rf "${data_dir:?}"/* "${data_dir:?}"/.[!.]* 2>/dev/null || true
  case "$gate" in
    validate)
      echo "== validate $d"
      terraform -chdir="$d" init -backend=false -input=false >/dev/null
      terraform -chdir="$d" validate
      ;;
    lint)
      echo "== tflint $d"
      tflint --chdir="$d" --config="$PWD/.tflint.hcl"
      ;;
    test)
      if has_tests "$d"; then
        echo "== test $d"
        terraform -chdir="$d" init -backend=false -input=false >/dev/null
        terraform -chdir="$d" test
      fi
      ;;
    versions)    check_versions "$d" || status=1 ;;
    dependabot)  check_dependabot "$d" || status=1 ;;
    *) echo "unknown gate: $gate" >&2; exit 2 ;;
  esac
done <<<"$dirs"
exit "$status"
