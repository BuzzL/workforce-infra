#!/usr/bin/env bash
# Proves the Makefile gates work: each passes on an empty tree and on valid stacks, and
# fails, for the expected reason, on the matching broken stack. Three stacks are built
# (first, middle and last in discovery order) so a gate that only checks the last
# directory is caught. Runs in a temp copy, so the repo is untouched.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$root/Makefile" "$root/.tflint.hcl" "$root/.terraform-version" "$root/scripts" "$work/"
cd "$work"

failed=0
# expect pass|fail[:pattern] <description> <command...>
expect() {
  local want=${1%%:*} pattern= desc=$2 got=pass
  [[ $1 == *:* ]] && pattern=${1#*:}
  shift 2
  "$@" >out.log 2>&1 || got=fail
  if [ "$got" != "$want" ]; then
    echo "FAIL $desc (wanted $want, got $got)"
    cat out.log
    failed=1
  elif [ -n "$pattern" ] && ! grep -q -- "$pattern" out.log; then
    echo "FAIL $desc (failed, but not because of: $pattern)"
    cat out.log
    failed=1
  else
    echo "ok   $desc"
  fi
}

write_stack() {
  mkdir -p "$1/tests"
  cat > "$1/versions.tf" <<'TF'
terraform {
  required_version = ">= 1.9"
}
TF
  cat > "$1/main.tf" <<'TF'
resource "terraform_data" "x" {
  input = "a"
}
TF
  cat > "$1/tests/x.tftest.hcl" <<'TF'
run "input_is_a" {
  command = plan
  assert {
    condition     = terraform_data.x.input == "a"
    error_message = "input must be a"
  }
}
TF
}

# Sorted discovery order: bootstrap, live/environments/development, modules/m
first=bootstrap
middle=live/environments/development
last=modules/m
write_valid() {
  rm -rf bootstrap live modules .github
  write_stack "$first"
  write_stack "$middle"
  write_stack "$last"
}
gates() { # gates <pass|fail> <label>
  local g
  for g in fmt validate lint versions dependabot test; do
    expect "$1" "$g $2" make "$g"
  done
}
dependabot_yml() { # dependabot_yml <directory entry>
  mkdir -p .github
  printf 'version: 2\nupdates:\n  - package-ecosystem: terraform\n    directories:\n      - %s\n' "$1" > .github/dependabot.yml
}

rm -rf bootstrap live modules
gates pass "empty tree"

write_valid
gates pass "three valid stacks"
expect pass "sec      valid stacks" make sec

# Each broken stack is not the last one, unless noted, so fail-fast in loops is proven.
write_valid
printf 'resource "terraform_data" "y" {\ninput   =   "b"\n}\n' >> "$last/main.tf"
expect fail:modules/m/main.tf "fmt      catches unformatted code (last dir)" make fmt

write_valid
printf 'output "bad" {\n  value = var.nope\n}\n' >> "$first/main.tf"
expect fail:"undeclared input variable" "validate catches an undeclared variable (first dir)" make validate

write_valid
printf 'terraform {}\n' > "$middle/versions.tf"
expect fail:terraform_required_version "lint     catches a missing required_version (middle dir)" make lint

write_valid
sed -i.bak 's/== "a"/== "b"/' "$last/tests/x.tftest.hcl"
expect fail:"input must be a" "test     catches a failing assertion (last dir)" make test

write_valid
printf 'terraform {\n  required_version = ">= 0.12"\n}\n' > "$first/versions.tf"
expect fail:'must be ">= 1.9"' "versions catches an old required_version (first dir)" make versions

write_valid
cat > "$middle/providers.tf" <<'TF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 1.0"
    }
  }
}
TF
expect fail:'pinned to "~> 6"' "versions catches an unpinned AWS provider (middle dir)" make versions
sed -i.bak 's/">= 1.0"/"~> 6.0"/' "$middle/providers.tf"
expect pass "versions accepts the AWS provider pinned to ~> 6" make versions

dependabot_yml /bootstrap
expect fail:"$middle: declares providers" "dependabot catches a stack missing from dependabot.yml" make dependabot
dependabot_yml '/live/environments/*'
expect pass "dependabot accepts a stack matched by a glob" make dependabot

write_valid
mkdir -p live/environments/production
echo '{"terraform":{"required_version":">= 0.1"}}' > live/environments/production/main.tf.json
expect fail:live/environments/production "versions discovers stacks written as *.tf.json" make versions

write_valid
cat > "$first/bucket.tf" <<'TF'
resource "aws_s3_bucket" "b" {
  bucket = "example"
}
TF
expect fail:HIGH "sec      catches a bucket without a public access block" make sec

exit "$failed"
