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
mkdir -p "$work/wf" && cp "$root/.github/workflows/terraform.yml" "$work/wf/terraform.yml"
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

# Sorted discovery order: bootstrap, live/environments/test, modules/m
first=bootstrap
middle=live/environments/test
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
mkdir -p live/environments/demo
echo '{"terraform":{"required_version":">= 0.1"}}' > live/environments/demo/main.tf.json
expect fail:live/environments/demo "versions discovers stacks written as *.tf.json" make versions

write_valid
cat > "$first/bucket.tf" <<'TF'
resource "aws_s3_bucket" "b" {
  bucket = "example"
}
TF
expect fail:HIGH "sec      catches a bucket without a public access block" make sec

# CI stack mapping: environments come from the path, unknown paths fail.
write_valid
rm -rf bootstrap live modules
write_stack bootstrap
write_stack live/management
write_stack bootstrap/accounts/security
write_stack bootstrap/accounts/workforce
write_stack live/accounts/security
write_stack live/environments/test
write_stack live/environments/quality
write_stack live/environments/demo
write_stack bootstrap/accounts/test
write_stack bootstrap/accounts/quality
write_stack bootstrap/accounts/demo
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks apply maps paths to environments"; else echo "FAIL ci-stacks apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plan lists only stacks with a plan environment"; else echo "FAIL ci-stacks plan mapping"; echo "$got"; failed=1; fi
# Account stacks stay out of CI until their .ci-enabled marker exists (checked above: absent). Then the
# account's own stack is applied by CI (apply true), planned in <account>-plan, and its baseline is not.
touch live/accounts/security/.ci-enabled
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"live/accounts/security","environment":"security","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks enables an account stack with its marker, and CI applies it"; else echo "FAIL ci-stacks account apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"live/accounts/security","environment":"security-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plans an enabled account baseline in <account>-plan"; else echo "FAIL ci-stacks account plan mapping"; echo "$got"; failed=1; fi
rm live/accounts/security/.ci-enabled
# The baseline stack of an account follows the same rule: local apply (apply false), planned in <account>-plan.
touch bootstrap/accounts/security/.ci-enabled
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"bootstrap/accounts/security","environment":"security","apply":false},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks enables an account's baseline stack with its marker, without apply"; else echo "FAIL ci-stacks baseline apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"bootstrap/accounts/security","environment":"security-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plans an enabled baseline stack in <account>-plan"; else echo "FAIL ci-stacks baseline plan mapping"; echo "$got"; failed=1; fi
rm bootstrap/accounts/security/.ci-enabled
# The environment accounts follow the same rule: their stacks join CI with their own marker. The baseline is
# planned in <name>-plan and never applied, the account's own stack is applied behind <name> and planned in <name>-plan.
for e in test quality demo; do touch bootstrap/accounts/$e/.ci-enabled live/environments/$e/.ci-enabled; done
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"bootstrap/accounts/demo","environment":"demo","apply":false},{"stack":"bootstrap/accounts/quality","environment":"quality","apply":false},{"stack":"bootstrap/accounts/test","environment":"test","apply":false},{"stack":"live/environments/demo","environment":"demo","apply":true},{"stack":"live/environments/quality","environment":"quality","apply":true},{"stack":"live/environments/test","environment":"test","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks enables the environment accounts with their markers"; else echo "FAIL ci-stacks environment apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"bootstrap/accounts/demo","environment":"demo-plan"},{"stack":"bootstrap/accounts/quality","environment":"quality-plan"},{"stack":"bootstrap/accounts/test","environment":"test-plan"},{"stack":"live/environments/demo","environment":"demo-plan"},{"stack":"live/environments/quality","environment":"quality-plan"},{"stack":"live/environments/test","environment":"test-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plans the environment accounts in <name>-plan"; else echo "FAIL ci-stacks environment plan mapping"; echo "$got"; failed=1; fi
for e in test quality demo; do rm bootstrap/accounts/$e/.ci-enabled live/environments/$e/.ci-enabled; done
expect fail:unmapped "ci-stacks does not map a baseline of an account outside the Environments OU" sh -c 'mkdir -p bootstrap/accounts/management && printf "terraform {}\n" > bootstrap/accounts/management/main.tf && scripts/ci-stacks.sh; rc=$?; rm -rf bootstrap/accounts/management; exit $rc'
# One marker is not enough: each stack joins CI with its own.
touch bootstrap/accounts/test/.ci-enabled
got=$(scripts/ci-stacks.sh apply)
case "$got" in *'"stack":"live/environments/test"'*) echo "FAIL ci-stacks: the baseline marker enabled the account's own stack"; failed=1 ;; *'"stack":"bootstrap/accounts/test"'*) echo "ok   ci-stacks: a baseline marker enables the baseline only" ;; *) echo "FAIL ci-stacks: the baseline marker did nothing"; failed=1 ;; esac
rm bootstrap/accounts/test/.ci-enabled
touch live/environments/test/.ci-enabled
got=$(scripts/ci-stacks.sh apply)
case "$got" in *'"stack":"bootstrap/accounts/test"'*) echo "FAIL ci-stacks: the stack marker enabled the baseline"; failed=1 ;; *'"stack":"live/environments/test"'*) echo "ok   ci-stacks: an account stack marker enables that stack only" ;; *) echo "FAIL ci-stacks: the stack marker did nothing"; failed=1 ;; esac
rm live/environments/test/.ci-enabled
expect fail:unmapped "ci-stacks does not map bootstrap/accounts/staging" sh -c 'mkdir -p bootstrap/accounts/staging && printf "terraform {}\n" > bootstrap/accounts/staging/main.tf && scripts/ci-stacks.sh; rc=$?; rm -rf bootstrap/accounts/staging; exit $rc'
expect fail:usage "ci-stacks rejects an unknown mode" scripts/ci-stacks.sh nonsense
# Gate: after a merge only the stacks whose plan has changes wait for an approval. Stacks here: bootstrap
# (drift check only), live/management and live/environments/test (applied by CI).
touch live/environments/test/.ci-enabled
gate() { printf '%s\n' "$@" | scripts/ci-stacks.sh gate; }
got=$(gate "bootstrap 0" "live/environments/test 0" "live/management 0")
if [ "$got" = "[]" ]; then echo "ok   ci-stacks gate: no change anywhere asks for no approval"; else echo "FAIL ci-stacks gate no-op"; echo "$got"; failed=1; fi
got=$(gate "bootstrap 0" "live/environments/test 2" "live/management 0")
want='[{"stack":"live/environments/test","environment":"test","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks gate: one changed stack asks once, for its own environment"; else echo "FAIL ci-stacks gate one change"; echo "$got"; failed=1; fi
got=$(gate "bootstrap 0" "live/environments/test 2" "live/management 2")
want='[{"stack":"live/environments/test","environment":"test","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks gate: every changed stack is kept"; else echo "FAIL ci-stacks gate two changes"; echo "$got"; failed=1; fi
expect fail:drift "ci-stacks gate fails on changes in a stack CI does not apply" gate "bootstrap 2" "live/environments/test 0" "live/management 0"
expect fail:drift "ci-stacks gate fails on drift even when another stack has changes to apply" gate "bootstrap 2" "live/environments/test 2" "live/management 0"
expect fail:failed "ci-stacks gate fails when a plan failed (exit code 1)" gate "bootstrap 0" "live/environments/test 1" "live/management 0"
expect fail:failed "ci-stacks gate fails on any other exit code" gate "bootstrap 0" "live/environments/test 0" "live/management 137"
expect fail:"no plan result" "ci-stacks gate fails on a missing result" gate "bootstrap 0" "live/management 0"
expect fail:"no plan result" "ci-stacks gate fails on empty input" gate ""
expect fail:"unknown stack" "ci-stacks gate fails on a result for an unknown stack" gate "bootstrap 0" "live/environments/test 0" "live/management 0" "live/other 0"
expect fail:duplicate "ci-stacks gate fails on a duplicated result" gate "bootstrap 0" "live/environments/test 0" "live/management 0" "live/management 2"
expect fail:invalid "ci-stacks gate fails on a result that is not a number" gate "bootstrap 0" "live/environments/test 0" "live/management x"
rm live/environments/test/.ci-enabled
# Names are explanatory, keys are four lowercase letters, unique (scripts/environment-keys.tsv).
# The shipped table passes (every mapping above), and each way of breaking it is refused.
printf 'quality\tEnvironments\tqa\tx\n' > bad-keys.tsv
expect fail:"four lowercase letters" "ci-stacks refuses a key that is not four letters" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'quality\tEnvironments\tQUAL\tx\n' > bad-keys.tsv
expect fail:"four lowercase letters" "ci-stacks refuses an uppercase key" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'quality\tEnvironments\tqualx\tx\n' > bad-keys.tsv
expect fail:"four lowercase letters" "ci-stacks refuses a five letter key" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'test\tEnvironments\ttest\tx\ndemo\tEnvironments\ttest\tx\n' > bad-keys.tsv
expect fail:"duplicate key" "ci-stacks refuses a duplicate key" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'quality\tStaging\tqual\tx\n' > bad-keys.tsv
expect fail:"unknown OU" "ci-stacks refuses an unknown OU" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'quality\tEnvironments\tqual\t\n' > bad-keys.tsv
expect fail:"description" "ci-stacks refuses an empty description" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'security\tManagement\tscrt\tx\n' > bad-keys.tsv
expect fail:"Environments OU" "ci-stacks refuses a table without an account in the Environments OU" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'test\tEnvironments\ttest\tx\ntest\tEnvironments\tdemo\tx\n' > bad-keys.tsv
expect fail:"duplicate name" "ci-stacks refuses a duplicate name" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'quality\tEnvironments\tqual\t \n' > bad-keys.tsv
expect fail:"description" "ci-stacks refuses a blank description" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
printf 'quality\tEnvironments\tqual\t\r\n' > bad-keys.tsv
expect fail:"description" "ci-stacks refuses an empty description in a CRLF file" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
# The stacks written above include live/environments/demo: it only maps if the last row (demo, no
# trailing newline) is kept, so a pass proves the row was read.
printf 'test\tEnvironments\ttest\tx\nquality\tEnvironments\tqual\tx\ndemo\tEnvironments\tdemo\tx' > bad-keys.tsv
expect pass "ci-stacks keeps a last row without a trailing newline" env ENV_KEYS_FILE=bad-keys.tsv scripts/ci-stacks.sh
rm bad-keys.tsv
# The key is not the name, and an account outside the Environments OU is not an environment:
# neither the retired qa, the key qual, nor management, security or workforce map to a stack.
for old in qa qual management security workforce; do
  rm -rf live/environments/$old
  mkdir -p live/environments/$old && printf 'terraform {}\n' > live/environments/$old/main.tf
  expect fail:unmapped "ci-stacks does not map live/environments/$old" scripts/ci-stacks.sh
  rm -rf live/environments/$old
done
# The accounts of the Organization stack and the table of names and keys are the same set.
cp "$root/live/management/accounts.tf" accounts.tf
mkdir -p fixture-root/bootstrap/accounts/quality
cp "$root/bootstrap/state_bucket.tf" fixture-root/bootstrap/
cp "$root/bootstrap/accounts/quality/main.tf" fixture-root/bootstrap/accounts/quality/
expect pass "check-accounts passes on the shipped accounts and table" env ACCOUNTS_FILE=accounts.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
sed 's/quality = "qual"/quality = "quax"/' fixture-root/bootstrap/state_bucket.tf > fixture-root/bootstrap/state_bucket.bad && mv fixture-root/bootstrap/state_bucket.bad fixture-root/bootstrap/state_bucket.tf
expect fail:"environment_keys" "check-accounts refuses a key in the bucket policy that the table does not have" env ACCOUNTS_FILE=accounts.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
cp "$root/bootstrap/state_bucket.tf" fixture-root/bootstrap/
sed 's/qual-foundation-infra-plan-role/qual-foundation-infra-other-role/' fixture-root/bootstrap/accounts/quality/main.tf > fixture-root/m && mv fixture-root/m fixture-root/bootstrap/accounts/quality/main.tf
expect fail:"must name the role" "check-accounts refuses a baseline stack whose role names do not carry the key" env ACCOUNTS_FILE=accounts.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
cp "$root/bootstrap/accounts/quality/main.tf" fixture-root/bootstrap/accounts/quality/
sed 's/^\(    demo  *= "Environments"\)$/\1\n    extra = "Environments"/' accounts.tf > accounts-extra.tf
cmp -s accounts.tf accounts-extra.tf && { echo "FAIL the accounts-extra fixture was not built"; failed=1; }
expect fail:"disagree" "check-accounts refuses an account with no row in the table" env ACCOUNTS_FILE=accounts-extra.tf ROOT_DIR=/nonexistent scripts/check-accounts.sh
grep -v '^demo	' scripts/environment-keys.tsv > keys-no-demo.tsv
expect fail:"disagree" "check-accounts refuses an account whose row is missing" env ACCOUNTS_FILE=accounts.tf ENV_KEYS_FILE=keys-no-demo.tsv scripts/check-accounts.sh
sed 's/^\(demo\)\tEnvironments/\1\tOperations/' scripts/environment-keys.tsv > keys-wrong-ou.tsv
expect fail:"disagree" "check-accounts refuses a row in another OU" env ACCOUNTS_FILE=accounts.tf ENV_KEYS_FILE=keys-wrong-ou.tsv scripts/check-accounts.sh
sed 's/^\(    demo  *= "Environments"\)$/\1 # a comment/' accounts.tf > accounts-comment.tf
cmp -s accounts.tf accounts-comment.tf && { echo "FAIL the accounts-comment fixture was not built"; failed=1; }
expect pass "check-accounts ignores a trailing comment on an account line" env ACCOUNTS_FILE=accounts-comment.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
printf '# nothing\n' > empty-accounts.tf
expect fail:"no account found" "check-accounts refuses a file with no accounts" env ACCOUNTS_FILE=empty-accounts.tf scripts/check-accounts.sh
mkdir -p fixture-root/live/environments/quality
cp "$root/live/environments/quality/main.tf" "$root/live/environments/quality/backend.hcl.example" fixture-root/live/environments/quality/
expect pass "check-accounts passes with the own stack of an environment" env ACCOUNTS_FILE=accounts.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
sed 's/key         = "qual"/key         = "quax"/' fixture-root/live/environments/quality/main.tf > fixture-root/m && mv fixture-root/m fixture-root/live/environments/quality/main.tf
expect fail:"must set key" "check-accounts refuses an own stack with another key than the table" env ACCOUNTS_FILE=accounts.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
cp "$root/live/environments/quality/main.tf" fixture-root/live/environments/quality/
sed 's#live/environments/quality#live/environments/qualx#' fixture-root/live/environments/quality/backend.hcl.example > fixture-root/m && mv fixture-root/m fixture-root/live/environments/quality/backend.hcl.example
expect fail:"backend.hcl.example must hold" "check-accounts refuses a backend key that is not the stack path" env ACCOUNTS_FILE=accounts.tf ROOT_DIR=fixture-root scripts/check-accounts.sh
rm -rf fixture-root
rm -f accounts.tf accounts-comment.tf accounts-extra.tf keys-no-demo.tsv keys-wrong-ou.tsv empty-accounts.tf
# The accounts MEMBER_ACCOUNT_IDS may name are the same in the script that sets the secret and in the variable of bootstrap/.
for acct in security workforce test quality demo; do
  grep -q "member_account_ids.*\"$acct\"" "$root/bootstrap/variables.tf" && grep -q "(security|workforce|test|quality|demo)" "$root/scripts/set-environment-secrets.sh" \
    && echo "ok   member accounts: $acct is accepted by bootstrap/variables.tf and set-environment-secrets.sh" || { echo "FAIL member accounts: $acct differs between bootstrap/variables.tf and set-environment-secrets.sh"; failed=1; }
done
expect fail:usage "account secrets script rejects a missing account" scripts/set-account-environment-secrets.sh
expect fail:usage "account secrets script rejects an unknown account" scripts/set-account-environment-secrets.sh management
expect fail:usage "account secrets script rejects an unknown option" scripts/set-account-environment-secrets.sh security --nonsense
printf 'name\tou\tkey\tdescription\ntest\tEnvironments\ttest\tx\n' > keys-no-quality.tsv
expect fail:"no four-letter key for quality" "account secrets script refuses an environment account without a key" env ENV_KEYS_FILE=keys-no-quality.tsv scripts/set-account-environment-secrets.sh quality
printf 'quality\tEnvironments\tqa\tx\n' > keys-short.tsv
expect fail:"no four-letter key for quality" "account secrets script refuses a key that is not four letters" env ENV_KEYS_FILE=keys-short.tsv scripts/set-account-environment-secrets.sh quality
rm -f keys-no-quality.tsv keys-short.tsv
write_stack live/other
expect fail:"unmapped stack: live/other" "ci-stacks rejects an unmapped stack" scripts/ci-stacks.sh
rm -rf live/other
write_stack live/environments/dev/nested
expect fail:"unmapped stack" "ci-stacks rejects a nested environment path" scripts/ci-stacks.sh plan
rm -rf live/environments/dev
write_stack live/environments/staging
expect fail:"unmapped stack: live/environments/staging" "ci-stacks rejects an environment that is not allowed" scripts/ci-stacks.sh
rm -rf live/environments/staging
write_stack live/environments/development
expect fail:"unmapped stack: live/environments/development" "ci-stacks rejects the former environment name development" scripts/ci-stacks.sh
rm -rf live/environments/development
# A directory name must not inject into the matrix or into a shell (job names, run scripts).
mkdir -p 'live/environments/x","environment":"management'
printf 'terraform {}\n' > 'live/environments/x","environment":"management/main.tf'
expect fail:"invalid stack name" "ci-stacks rejects a directory name that injects JSON" scripts/ci-stacks.sh
rm -rf live/environments/x*
mkdir -p 'live/environments/a$(id)'
printf 'terraform {}\n' > 'live/environments/a$(id)/main.tf'
expect fail:"invalid stack name" "ci-stacks rejects a directory name with shell syntax" scripts/ci-stacks.sh
rm -rf live/environments/a*

# Redaction: what must not reach a public log, artifact or comment.
redacted=$(printf '%s\n' \
  'id=arn:aws:iam::123456789012:role/x AROAABCDEFGHIJKLMNOP:GitHubActions' \
  "Assumed AS""IAABCDEFGHIJKLMNOP token" \
  'bucket workforce-tfstate-a1b2c3d4 and other-bucket-77 and workforce-audit-logs-x9y8 and my-logs-55' \
  'parent_id = "r-ab12" ou-ab12-cdef5678 for-r-abcd' \
  'a r-ab12 r-cd34 ou-ab12-cdef5678,ou-ab12-cdef5679 arn:aws:organizations::111122223333:ou/o-abcdefghij/ou-ab12-cdef5678' \
  'r-ab12 r-cd34,ou-ab12-cdef5678,ou-ab12-cdef5679 arn:aws:organizations::x:ou/o-abcdefghij/ou-ab12-cdef5678' \
  'contact me@example.com sub repo:BuzzL@6116516/workforce-infra@1394667495:environment:m' \
  'instance_arn = arn:aws:sso:::instance/ssoins-1a2b3c4d5e6f7a8b ps-1a2b3c4d5e6f7a8b principal_id = 11111111-2222-3333-4444-555555555555' \
  'external_ids = ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"] 123456789012' \
  '  ~ resource "aws_iam_role" "x" {' | STATE_BUCKET=other-bucket-77 AUDIT_LOG_BUCKET=my-logs-55 scripts/redact.sh)
want_redacted=$(printf '%s\n' \
  'id=arn:aws:iam::<account-id>:role/x <aws-id>:GitHubActions' \
  'Assumed <aws-id> token' \
  'bucket <state-bucket> and <state-bucket> and <audit-log-bucket> and <audit-log-bucket>' \
  'parent_id = "<org-id>" <org-id> for-r-abcd' \
  'a <org-id> <org-id> <org-id>,<org-id> arn:aws:organizations::<account-id>:ou/<org-id>/<org-id>' \
  '<org-id> <org-id>,<org-id>,<org-id> arn:aws:organizations::x:ou/<org-id>/<org-id>' \
  'contact <email> sub repo:BuzzL@6116516/workforce-infra@1394667495:environment:m' \
  'instance_arn = arn:aws:sso:::instance/<sso-id> <sso-id> principal_id = <uuid>' \
  'external_ids = ["<external-id>"] <account-id>' \
  '  ~ resource "aws_iam_role" "x" {')
if [ "$redacted" = "$want_redacted" ]; then echo "ok   redact hides account IDs, unique IDs, ExternalIds, bucket names, Organization IDs and emails only"; else echo "FAIL redact"; echo "$redacted"; failed=1; fi

# The public-docs gate passes on placeholders and refuses an account ID, an ARN with an ID and an email.
mkdir -p docs-ok docs-id docs-arn docs-mail docs-sep docs-letters docs-13 docs-gov
echo 'role arn:aws:iam::<account-id>:role/test-agent in <workforce-account-id>' > docs-ok/A.md
echo 'account 123456789012 here' > docs-id/A.md
echo 'arn:aws:iam::123456789012:role/x' > docs-arn/A.md
echo 'mail someone@example.com' > docs-mail/A.md
echo 'account 1234-5678-9012 here' > docs-sep/A.md
echo 'idx123456789012y' > docs-letters/A.md
echo 'number 1234567890123 is 13 digits' > docs-13/A.md
echo 'arn:aws-us-gov:iam::123456789012:role/x' > docs-gov/A.md
expect pass "docs: placeholders are accepted" scripts/check-docs-public.sh docs-ok
expect fail:"12-digit" "docs: an account ID is refused" scripts/check-docs-public.sh docs-id
expect fail:"ARN with an account ID" "docs: an ARN with an ID is refused" scripts/check-docs-public.sh docs-arn
expect fail:"email address" "docs: an email is refused" scripts/check-docs-public.sh docs-mail
expect fail:"separators" "docs: an ID with separators is refused" scripts/check-docs-public.sh docs-sep
expect fail:"12-digit" "docs: an ID next to letters is refused" scripts/check-docs-public.sh docs-letters
expect fail:"no such directory" "docs: a missing directory is an error, not a pass" scripts/check-docs-public.sh docs-missing
expect pass "docs: a 13-digit number is not an account ID" scripts/check-docs-public.sh docs-13
expect fail:"ARN with an account ID" "docs: an ARN of another partition is refused" scripts/check-docs-public.sh docs-gov

# Structure of the workflow: it passes as written and each mutation is rejected.
expect pass "workflow structure holds" scripts/check-workflow.sh "$work/wf/terraform.yml"
python3 - "$work" "$root" <<'PY' || failed=1
import subprocess, sys
work, root = sys.argv[1], sys.argv[2]
src = open(work + "/wf/terraform.yml").read()
CHECK = root + "/scripts/check-workflow.sh"
PLAN_PERMS = "    permissions:\n      id-token: write\n      contents: read\n    env:"
CASES = [
    ("plan job cannot write to pull requests", PLAN_PERMS, "    permissions:\n      id-token: write\n      contents: read\n      pull-requests: write\n    env:", "plan: permissions must be exactly"),
    ("plan job cannot have write-all", PLAN_PERMS, "    permissions: write-all\n    env:", "plan: permissions must be exactly"),
    ("plan job cannot write issues (comments)", PLAN_PERMS, "    permissions:\n      id-token: write\n      contents: read\n      issues: write\n    env:", "plan: permissions must be exactly"),
    ("no workflow-level write", "permissions: {}\n\njobs:", "permissions:\n  pull-requests:  write\n\njobs:", "workflow-level permissions"),
    ("forks must be skipped, however the condition is written", "github.event.pull_request.head.repo.full_name == github.repository)) &&", "(github.event.pull_request.head.repo.full_name == github.repository || true))) &&", "plan: the condition"),
    ("Apply guard cannot be widened", "if: matrix.apply == true && steps.plan", "if: matrix.apply == true || steps.plan", "Apply must be guarded"),
    ("the account ID stays masked, even next to a comment", "mask-aws-account-id: true", "mask-aws-account-id: false # mask-aws-account-id: true", "must mask the account ID"),
    ("the role stays a secret (bracket syntax)", "role-to-assume: ${{ secrets.AWS_ROLE_ARN }}", "role-to-assume: ${{ vars['AWS_ROLE_ARN'] }}", "must come from the secret"),
    ("only AWS_REGION is a variable (any case)", "TF_VAR_state_bucket_name: ${{ secrets.STATE_BUCKET }}", "TF_VAR_state_bucket_name: ${{ vars.state_bucket }}", "variable not allowed"),
    ("an action owner cannot change case", "hashicorp/setup-terraform@dfe3", "HashiCorp/setup-terraform@dfe3", "action not allowed"),
    ("an action must be pinned by SHA", "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1", "actions/checkout@v7", "not pinned by commit SHA"),
    ("no unknown action after the credentials", "      - name: Init\n", "      - uses: some/action@v1\n      - name: Init\n", "action not allowed"),
    ("no script that encodes a secret", "      - name: Init\n", "      - run: echo \"$STATE_BUCKET\" | base64\n      - name: Init\n", "could print or send values"),
    ("-lock=false cannot hide in a comment", "-input=false -lock=false -no-color -detailed-exitcode 2>&1", "-input=false -no-color -detailed-exitcode # -lock=false\n          echo 2>&1", "-lock=false"),
    ("terraform output goes through the redaction", '2>&1 | "$GITHUB_WORKSPACE/scripts/redact.sh" | tee', "2>&1 | tee", "must go through scripts/redact.sh"),
    ("the Organization root ID stays a secret", "TF_VAR_root_id: ${{ secrets.ORGANIZATION_ROOT_ID }}", 'TF_VAR_root_id: "r-ab12"', "the Organization root ID must be a secret"),
    ("the account email base stays a secret", "TF_VAR_account_email_base: ${{ secrets.ACCOUNT_EMAIL_BASE }}", 'TF_VAR_account_email_base: "a@b.c"', "the account email base must be a secret"),
    ("the member account IDs stay a secret", "TF_VAR_member_account_ids: ${{ secrets.MEMBER_ACCOUNT_IDS || '{}' }}", 'TF_VAR_member_account_ids: "{}"', "the member account IDs must be a secret"),
    ("the budget alert address stays a secret", "TF_VAR_budget_alert_email: ${{ secrets.BUDGET_ALERT_EMAIL }}", 'TF_VAR_budget_alert_email: "a@b.co"', "the budget alert address must be a secret"),
    ("the maintainer user name stays a secret", "TF_VAR_maintainer_username: ${{ secrets.MAINTAINER_USERNAME }}", 'TF_VAR_maintainer_username: "someone"', "the maintainer user name must be a secret"),
    ("the assignment account IDs stay a secret", "TF_VAR_assignment_account_ids: ${{ secrets.ASSIGNMENT_ACCOUNT_IDS || '{}' }}", 'TF_VAR_assignment_account_ids: "{}"', "the assignment account IDs must be a secret"),
    ("the audit log bucket name stays a secret", "TF_VAR_audit_log_bucket_name: ${{ secrets.AUDIT_LOG_BUCKET }}", 'TF_VAR_audit_log_bucket_name: "some-bucket"', "the audit log bucket name must be a secret"),
    ("the audit log bucket stays referenced so that it is masked", "      AUDIT_LOG_BUCKET: ${{ secrets.AUDIT_LOG_BUCKET }}", '      AUDIT_LOG_BUCKET: ""', "AUDIT_LOG_BUCKET must be referenced"),
    ("the Organization ID stays a secret", "TF_VAR_organization_id: ${{ secrets.ORGANIZATION_ID }}", 'TF_VAR_organization_id: "o-abcdef1234"', "the Organization ID must be a secret"),
    ("the management account ID stays a secret", "TF_VAR_management_account_id: ${{ secrets.MANAGEMENT_ACCOUNT_ID }}", 'TF_VAR_management_account_id: "111122223333"', "the management account ID must be a secret"),
    ("the role ID stays referenced so that it is masked", "AWS_ROLE_ID: ${{ secrets.AWS_ROLE_ID }}", 'AWS_ROLE_ID: ""', "AWS_ROLE_ID must be referenced"),
    ("checkout does not persist credentials", "        with:\n          persist-credentials: false\n", "        with: {}\n", "must not persist credentials"),
    ("the comment job only posts a finished plan", "needs.plan.result == 'failure')", "needs.plan.result == 'failure' || true)", "comment: it must only post a finished plan"),
    ("the comment is updated in place", "--edit-last --create-if-none", "--create-if-none", "updated in place"),
    ("changes has no environment, so it never waits for an approval", "  changes:\n    needs: plan\n", "  changes:\n    needs: plan\n    environment: management\n", "changes: it must have no environment"),
    ("changes cannot get AWS credentials", "  changes:\n    needs: plan\n    if: github.event_name == 'push'\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n", "  changes:\n    needs: plan\n    if: github.event_name == 'push'\n    runs-on: ubuntu-latest\n    permissions:\n      id-token: write\n      contents: read\n", "changes: permissions must be exactly"),
    ("changes only runs after a merge", "  changes:\n    needs: plan\n    if: github.event_name == 'push'", "  changes:\n    needs: plan\n    if: always()", "changes: it must only run on push"),
    ("changes does not run after a failed plan", "  changes:\n    needs: plan\n", "  changes:\n    needs: [discover, plan]\n", "changes: it must wait for the plans"),
    ("changes passes the plan results through the gate", "scripts/ci-stacks.sh gate", "scripts/ci-stacks.sh apply", "must go through scripts/ci-stacks.sh gate"),
    ("apply waits for changes, not only for the stack list", "  apply:\n    needs: changes\n", "  apply:\n    needs: discover\n", "apply: it must wait for changes"),
    ("apply only runs the stacks that changes passed", "fromJSON(needs.changes.outputs.apply_stacks)", "fromJSON(needs.discover.outputs.plan_stacks)", "apply: the matrix must be the stacks that changes passed"),
    ("changes downloads every plan artifact", "          pattern: plan-*\n          merge-multiple: true\n          path: plans\n      - id: gate", "          pattern: plan-1\n          merge-multiple: true\n          path: plans\n      - id: gate", "changes: it must download every plan artifact"),
    ("changes fails when the gate fails", "          set -euo pipefail\n          apply=$(cat", "          apply=$(cat", "changes: the gate step must fail on a failed gate"),
    ("changes passes on the output of the gate", "apply_stacks: ${{ steps.gate.outputs.apply }}", "apply_stacks: '[]'", "changes: apply_stacks must be the output of the gate"),
    ("the plan job uploads its result file", "            ${{ runner.temp }}/result-${{ strategy.job-index }}.txt\n", "", "plan: the result file must be uploaded"),
    ("the plan job gets the agent role from the secret AGENT", "TF_VAR_agent: ${{ secrets.AGENT || 'null' }}", "TF_VAR_agent: ${{ secrets.AGENT }}", "plan: the agent role must come from the secret AGENT"),
    ("the agent role is not hardcoded", "TF_VAR_agent: ${{ secrets.AGENT || 'null' }}", "TF_VAR_agent: 'null'", "plan: the agent role must come from the secret AGENT"),
    ("the apply job never receives the agent role", "      STACK: ${{ matrix.stack }}\n    defaults:", "      TF_VAR_agent: ${{ secrets.AGENT || 'null' }}\n      STACK: ${{ matrix.stack }}\n    defaults:", "apply: it must not receive the agent role"),
    ("the comment is only posted on a pull request", "always() && github.event_name == 'pull_request' &&", "always() &&", "comment: it must only post a finished plan"),
    ("an apply is never cancelled", "cancel-in-progress: false", "cancel-in-progress: true", "never be cancelled"),
    ("only the comment job uses github.token", "      STACK: ${{ matrix.stack }}\n      INDEX", "      X: ${{ github.token }}\n      STACK: ${{ matrix.stack }}\n      INDEX", "only the comment job may use github.token"),
    ("no manual trigger", "on:\n  pull_request:", "on:\n  workflow_dispatch:\n  pull_request:", "only the pull_request and push triggers"),
    ("no template expression inside a script", 'The plan for $STACK has changes', "The plan for ${{ matrix.stack }} has changes", "expression inside a run script"),
]
bad = 0
for desc, a, b, pattern in CASES:
    if a not in src:
        print("FAIL workflow: %s (mutation target not found)" % desc); bad = 1; continue
    open(work + "/wf/mutated.yml", "w").write(src.replace(a, b, 1))
    r = subprocess.run([CHECK, work + "/wf/mutated.yml"], capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode == 0:
        print("FAIL workflow: %s (the mutation passed)" % desc); bad = 1
    elif pattern not in out:
        print("FAIL workflow: %s (rejected, but not for: %s)\n%s" % (desc, pattern, out)); bad = 1
    else:
        print("ok   workflow: " + desc)
sys.exit(bad)
PY

# prevent_destroy guard: each resource block is judged on its own.
pd_tree() { mkdir -p "$1/live/a"; printf '%s\n' "$2" > "$1/live/a/main.tf"; }
pd_tree pd-ok 'resource "aws_organizations_account" "this" {
  name = "${var.name}-{x}"
  lifecycle {
    prevent_destroy = true
  }
}'
pd_tree pd-missing 'resource "aws_organizations_account" "this" {
  name = "x"
}'
pd_tree pd-second 'resource "aws_organizations_account" "first" {
  name = "x"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_account_assignment" "second" {
  instance_arn = "x"
}'
pd_tree pd-other 'resource "aws_iam_role" "ci" {
  name = "x"
}'
pd_tree pd-false 'resource "aws_s3_bucket" "logs" {
  bucket = "x"
  lifecycle {
    prevent_destroy = false
  }
}'
pd_tree pd-comment 'resource "aws_organizational_unit_x" "y" {
}
resource "aws_ssoadmin_permission_set" "this" {
  name = "x"
  # prevent_destroy = true
}'
pd_tree pd-string 'resource "aws_s3_bucket" "logs" {
  tags = { note = "prevent_destroy = true" }
}'
pd_tree pd-trueish 'resource "aws_s3_bucket" "logs" {
  lifecycle {
    prevent_destroy = true && false
  }
}'
pd_tree pd-trail 'resource "aws_cloudtrail" "this" {
  name = "x"
}'
mkdir -p pd-tests/live/a/tests && printf 'resource "aws_organizations_account" "t" {\n}\n' > pd-tests/live/a/tests/x.tf
expect pass "prevent_destroy: a guarded resource passes, braces in strings do not confuse it" scripts/check-prevent-destroy.sh pd-ok
expect pass "prevent_destroy: a type that is not listed (the local baseline roles) passes" scripts/check-prevent-destroy.sh pd-other
expect pass "prevent_destroy: test fixtures are not stacks" scripts/check-prevent-destroy.sh pd-tests
expect fail:"aws_organizations_account.this must carry" "prevent_destroy: an unguarded account is refused" scripts/check-prevent-destroy.sh pd-missing
expect fail:"aws_ssoadmin_account_assignment.second must carry" "prevent_destroy: a guarded resource does not cover the next one in the file" scripts/check-prevent-destroy.sh pd-second
expect fail:"aws_s3_bucket.logs must carry" "prevent_destroy: = false is not a guard" scripts/check-prevent-destroy.sh pd-false
expect fail:"aws_ssoadmin_permission_set.this must carry" "prevent_destroy: a commented line is not a guard" scripts/check-prevent-destroy.sh pd-comment
expect fail:"aws_s3_bucket.logs must carry" "prevent_destroy: the text inside a string is not a guard" scripts/check-prevent-destroy.sh pd-string
expect fail:"aws_s3_bucket.logs must carry" "prevent_destroy: = true && false is not a guard" scripts/check-prevent-destroy.sh pd-trueish
expect fail:"aws_cloudtrail.this must carry" "prevent_destroy: the audit trail is listed" scripts/check-prevent-destroy.sh pd-trail

# The CODEOWNERS gate passes on the shipped file and refuses a missing path, a stale entry, a rule
# with no owner and a catch-all that is not first.
mkdir -p co-root/bootstrap co-root/modules/account-ci-baseline co-root/.github co-root/scripts && touch co-root/Makefile
cp "$root/.github/CODEOWNERS" co-ok
expect pass "codeowners: the shipped file passes" env CODEOWNERS_FILE=co-ok CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
grep -v '^/bootstrap/' co-ok > co-unlisted
expect fail:"/bootstrap/ is not listed" "codeowners: an unlisted protected path is refused" env CODEOWNERS_FILE=co-unlisted CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
rm -rf co-root/scripts
expect fail:"/scripts/ does not exist" "codeowners: a path that no longer exists is refused" env CODEOWNERS_FILE=co-ok CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
mkdir -p co-root/scripts
sed 's|^/Makefile .*|/Makefile|' co-ok > co-noowner
expect fail:"/Makefile has no owner" "codeowners: a rule with no owner is refused" env CODEOWNERS_FILE=co-noowner CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
grep -v '^\*' co-ok > co-nocatch
expect fail:"first rule must be the catch-all" "codeowners: no catch-all first is refused" env CODEOWNERS_FILE=co-nocatch CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
sed 's|^/Makefile .*|/Makefile  # todo|' co-ok > co-inline
expect fail:"/Makefile has no owner" "codeowners: an inline comment is not an owner" env CODEOWNERS_FILE=co-inline CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
sed 's|^/Makefile .*|/Makefile  BuzzL|' co-ok > co-bare
expect fail:"is not an @user" "codeowners: an owner without @ is refused" env CODEOWNERS_FILE=co-bare CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
{ cat co-ok; printf '*.tf  @BuzzL\n'; } > co-glob
expect pass "codeowners: a glob pattern is accepted, not looked up on disk" env CODEOWNERS_FILE=co-glob CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh
expect fail:"no such file" "codeowners: a missing file is an error, not a pass" env CODEOWNERS_FILE=co-missing CODEOWNERS_ROOT=co-root scripts/check-codeowners.sh

# set-agent-role-vars.sh: creates, keeps, rotates and drops ExternalIds without printing them.
agent_root=ag-root
rm -rf "$agent_root" && mkdir -p "$agent_root/scripts" "$agent_root/bootstrap/accounts"/{test,quality,demo}
cp scripts/set-agent-role-vars.sh "$agent_root/scripts/"
agent_arn=arn:aws:iam::444455556666:role/platform/wrkf-foundation-agent-role
agent() { env AGENT_ROLE_ARN="${AGENT_ROLE_ARN-$agent_arn}" "$agent_root/scripts/set-agent-role-vars.sh" "$@"; }
ids() { grep -oE '"[0-9a-f]{64}"' "$agent_root/bootstrap/accounts/$1/terraform.tfvars" | tr -d '"'; }
printf 'region = "eu-west-1"\n' > "$agent_root/bootstrap/accounts/test/terraform.tfvars"
expect pass "agent vars: create writes the three stacks" agent
expect pass "agent vars: an existing tfvars keeps its other lines" grep -q '^region = "eu-west-1"' "$agent_root/bootstrap/accounts/test/terraform.tfvars"
expect pass "agent vars: one ExternalId of 64 hex characters each" test "$(ids test | wc -l)" -eq 1 -a "$(ids quality | wc -l)" -eq 1
expect pass "agent vars: the files are private (600)" test "$(stat -c %a "$agent_root/bootstrap/accounts/demo/terraform.tfvars" 2>/dev/null || stat -f %Lp "$agent_root/bootstrap/accounts/demo/terraform.tfvars")" = 600
expect pass "agent vars: every environment has its own ExternalId" test "$(for a in test quality demo; do ids $a; done | sort -u | wc -l)" -eq 3
first_id=$(ids test)
cp "$agent_root/bootstrap/accounts/test/terraform.tfvars" before.tfvars
expect pass "agent vars: a second run changes nothing" agent
expect pass "agent vars: ...not even a byte of the file" cmp before.tfvars "$agent_root/bootstrap/accounts/test/terraform.tfvars"
expect fail:"principal differs" "agent vars: another principal is refused, not swapped in" env AGENT_ROLE_ARN=arn:aws:iam::444455556666:role/platform/wrkf-other-role "$agent_root/scripts/set-agent-role-vars.sh"
expect pass "agent vars: no temporary file is left behind" test -z "$(find "$agent_root/bootstrap" -name 'tmp.*')"
expect pass "agent vars: the ExternalId is kept" test "$(ids test)" = "$first_id"
agent --check > check.out 2>&1 || true
expect pass "agent vars: --check never prints a value" test -z "$(grep -E '[0-9a-f]{64}' check.out)"
expect pass "agent vars: --rotate adds one in front and keeps the current one" bash -c "$(declare -f agent ids); agent_root=$agent_root; agent_arn=$agent_arn; agent --rotate && test \"\$(ids test | wc -l)\" -eq 2 && test \"\$(ids test | tail -n 1)\" = $first_id"
expect fail:"needs exactly one" "agent vars: --rotate twice in a row is refused" agent --rotate
new_id=$(ids test | head -n 1)
expect pass "agent vars: --drop-old keeps the new one only" bash -c "$(declare -f agent ids); agent_root=$agent_root; agent_arn=$agent_arn; agent --drop-old && test \"\$(ids test)\" = $new_id"
expect fail:"not the ARN of a wrkf" "agent vars: a principal that is not a wrkf role is refused" env AGENT_ROLE_ARN=arn:aws:iam::444455556666:root "$agent_root/scripts/set-agent-role-vars.sh"
expect fail:"usage" "agent vars: an unknown option is refused" agent --nope
# Files the markers cannot be trusted on are refused and left as they are.
bad=$agent_root/bootstrap/accounts/demo/terraform.tfvars
cp "$bad" good.tfvars
printf 'agent = null\n' > "$bad"
expect fail:"outside the markers" "agent vars: a hand-written agent is refused" agent
printf '%s\r\nregion = "x"\r\n' "# BEGIN agent (scripts/set-agent-role-vars.sh)" > "$bad"
expect fail:"CRLF" "agent vars: CRLF is refused" agent
printf '# BEGIN agent (scripts/set-agent-role-vars.sh)\nb = 2\n' > "$bad"
expect fail:"unbalanced" "agent vars: a block without END is refused, nothing after it is lost" agent
expect pass "agent vars: ...and the file is untouched" grep -q '^b = 2' "$bad"
printf 'region = "x"' > "$bad"
expect pass "agent vars: a file without a trailing newline gets the block" agent
expect pass "agent vars: ...and keeps its own line" grep -q '^region = "x"' "$bad"
cp good.tfvars "$bad"
expect pass "agent vars: the principal and account are written" grep -q "principal_arn        = \"$agent_arn\"" "$agent_root/bootstrap/accounts/quality/terraform.tfvars"

# --set-secrets: the secret AGENT of each <name>-plan environment, through gh on stdin, never printed.
mkdir -p fake-gh
cat > fake-gh/gh <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> gh.args
cat > "gh.in.$(date +%s%N)"
SH
chmod +x fake-gh/gh
rm -f gh.args gh.in.*
expect pass "agent vars: --set-secrets sets AGENT in the three plan environments" env PATH="$PWD/fake-gh:$PATH" AGENT_ROLE_ARN= "$agent_root/scripts/set-agent-role-vars.sh" --set-secrets
expect pass "agent vars: ...one call per <name>-plan environment, by name" test "$(sort gh.args | tr '\n' '|')" = "secret set AGENT --repo BuzzL/workforce-infra --env demo-plan|secret set AGENT --repo BuzzL/workforce-infra --env quality-plan|secret set AGENT --repo BuzzL/workforce-infra --env test-plan|"
expect pass "agent vars: ...the value is on stdin, in the shape Terraform reads from TF_VAR_agent" grep -qE '^\{principal_arn="arn:aws:iam::[0-9]{12}:role/platform/wrkf-foundation-agent-role",workforce_account_id="444455556666",external_ids=\["[0-9a-f]{64}"\]\}$' gh.in.*
expect pass "agent vars: ...the value is never on a command line" test -z "$(grep -E '[0-9a-f]{64}|444455556666' gh.args)"
env PATH="$PWD/fake-gh:$PATH" "$agent_root/scripts/set-agent-role-vars.sh" --set-secrets > secrets.out 2>&1 || true
expect pass "agent vars: ...and never printed" test -z "$(grep -E '[0-9a-f]{64}|arn:aws' secrets.out)"
cp "$agent_root/bootstrap/accounts/test/terraform.tfvars" before.tfvars
printf 'region = "x"\n' > "$agent_root/bootstrap/accounts/test/terraform.tfvars"
expect fail:"no agent block" "agent vars: --set-secrets without a block is refused" env PATH="$PWD/fake-gh:$PATH" "$agent_root/scripts/set-agent-role-vars.sh" --set-secrets
cp before.tfvars "$agent_root/bootstrap/accounts/test/terraform.tfvars"
sed -i.bak 's/wrkf-foundation-agent-role/other-role/' "$agent_root/bootstrap/accounts/test/terraform.tfvars"
expect fail:"expected shape" "agent vars: --set-secrets refuses a block that is not in the expected shape" env PATH="$PWD/fake-gh:$PATH" "$agent_root/scripts/set-agent-role-vars.sh" --set-secrets
cp before.tfvars "$agent_root/bootstrap/accounts/test/terraform.tfvars"

exit "$failed"
