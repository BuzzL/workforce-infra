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
write_stack live/accounts/security
write_stack live/accounts/workforce
write_stack live/environments/test
write_stack live/environments/quality
write_stack live/environments/demo
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"live/environments/demo","environment":"demo","apply":true},{"stack":"live/environments/quality","environment":"quality","apply":true},{"stack":"live/environments/test","environment":"test","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks apply maps paths to environments"; else echo "FAIL ci-stacks apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plan lists only stacks with a plan environment"; else echo "FAIL ci-stacks plan mapping"; echo "$got"; failed=1; fi
# Account baselines stay out of CI until their .ci-enabled marker exists (checked above: absent), and
# then are only planned (apply false), under their own <account>-plan environment.
touch live/accounts/security/.ci-enabled
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"live/accounts/security","environment":"security","apply":false},{"stack":"live/environments/demo","environment":"demo","apply":true},{"stack":"live/environments/quality","environment":"quality","apply":true},{"stack":"live/environments/test","environment":"test","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks enables an account baseline with its marker, without apply"; else echo "FAIL ci-stacks account apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"live/accounts/security","environment":"security-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plans an enabled account baseline in <account>-plan"; else echo "FAIL ci-stacks account plan mapping"; echo "$got"; failed=1; fi
rm live/accounts/security/.ci-enabled
expect fail:usage "ci-stacks rejects an unknown mode" scripts/ci-stacks.sh nonsense
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
expect fail:usage "account secrets script rejects a missing account" scripts/set-account-environment-secrets.sh
expect fail:usage "account secrets script rejects an unknown account" scripts/set-account-environment-secrets.sh management
expect fail:usage "account secrets script rejects an unknown option" scripts/set-account-environment-secrets.sh security --nonsense
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
  '  ~ resource "aws_iam_role" "x" {')
if [ "$redacted" = "$want_redacted" ]; then echo "ok   redact hides account IDs, unique IDs, bucket names, Organization IDs and emails only"; else echo "FAIL redact"; echo "$redacted"; failed=1; fi

# The docs gate: a clean tree passes, and each kind of mess is refused for its own reason.
# docs_tree <dir> <file> <content>: a minimal clean tree with one doc, then <file> replaced by <content>.
docs_tree() {
  mkdir -p "$1/docs"
  printf '# Good\n\nA clean document.\n' > "$1/docs/GOOD_DOC.md"
  printf '# Repo\n\n- `docs/GOOD_DOC.md`: a clean document.\n' > "$1/CLAUDE.md"
  [ -z "${2:-}" ] || printf '%s\n' "$3" > "$1/$2"
}
docs_tree docs-ok
docs_tree docs-example docs/EXAMPLE_DOC.md 'mail owner@example.com, `docs/GOOD_DOC.md`, `live/environments/test` and `<acct>` are fine'
printf '%s\n' '- `docs/EXAMPLE_DOC.md`: x' >> docs-example/CLAUDE.md
docs_tree docs-id docs/GOOD_DOC.md 'account 123456789012 here'
docs_tree docs-sep docs/GOOD_DOC.md 'account 1234-5678-9012 here'
docs_tree docs-letters docs/GOOD_DOC.md 'idx123456789012y'
docs_tree docs-13 docs/GOOD_DOC.md 'number 1234567890123 is 13 digits'
docs_tree docs-arn docs/GOOD_DOC.md 'arn:aws:iam::123456789012:role/x'
docs_tree docs-gov docs/GOOD_DOC.md 'arn:aws-us-gov:iam::123456789012:role/x'
docs_tree docs-mail docs/GOOD_DOC.md 'mail someone@gmail.com'
docs_tree docs-ticket docs/GOOD_DOC.md 'done in IAT-12'
docs_tree docs-trivy docs/GOOD_DOC.md 'Trivy AWS-0015 is waived'
docs_tree docs-milestone docs/GOOD_DOC.md 'comes in M3'
docs_tree docs-todo docs/GOOD_DOC.md 'TODO write this'
docs_tree docs-qa docs/GOOD_DOC.md 'deploy to qa first'
docs_tree docs-qa-ok docs/GOOD_DOC.md 'qa was renamed quality'
docs_tree docs-name docs/bad-name.md 'a clean document'
printf '%s\n' '- `docs/bad-name.md`: x' >> docs-name/CLAUDE.md
docs_tree docs-orphan docs/ORPHAN.md 'a clean document'
docs_tree docs-dead docs/GOOD_DOC.md 'see `scripts/missing.sh` and `docs/NOPE.md`'
docs_tree docs-local docs/GOOD_DOC.md 'edit `live/management/terraform.tfvars` and `bootstrap/backend.hcl`'
mkdir -p docs-example/live/management && echo 'x = "owner@example.com"' > docs-example/live/management/terraform.tfvars.example
mkdir -p docs-example-bad && docs_tree docs-example-bad && echo 'x = "owner@gmail.com"' > docs-example-bad/a.tfvars.example
expect pass "docs: a clean tree passes" scripts/check-docs.sh docs-ok
expect pass "docs: example.com, placeholders and local paths are accepted" scripts/check-docs.sh docs-example
expect pass "docs: qa next to quality (the rename) is accepted" scripts/check-docs.sh docs-qa-ok
expect pass "docs: files that are never committed are not looked up" scripts/check-docs.sh docs-local
expect pass "docs: a 13-digit number is not an account ID" scripts/check-docs.sh docs-13
expect pass "docs: tool IDs such as AWS-0015 are not tickets" scripts/check-docs.sh docs-trivy
expect fail:"12-digit" "docs: an account ID is refused" scripts/check-docs.sh docs-id
expect fail:"separators" "docs: an ID with separators is refused" scripts/check-docs.sh docs-sep
expect fail:"12-digit" "docs: an ID next to letters is refused" scripts/check-docs.sh docs-letters
expect fail:"ARN with an account ID" "docs: an ARN with an ID is refused" scripts/check-docs.sh docs-arn
expect fail:"ARN with an account ID" "docs: an ARN of another partition is refused" scripts/check-docs.sh docs-gov
expect fail:"email address" "docs: an email is refused" scripts/check-docs.sh docs-mail
expect fail:"email address" "docs: an email in an example file is refused" scripts/check-docs.sh docs-example-bad
expect fail:"ticket ID" "docs: a ticket ID is refused" scripts/check-docs.sh docs-ticket
expect fail:"milestone" "docs: a milestone number is refused" scripts/check-docs.sh docs-milestone
expect fail:"unfinished marker" "docs: a TODO is refused" scripts/check-docs.sh docs-todo
expect fail:"not qa" "docs: the qa environment is refused" scripts/check-docs.sh docs-qa
expect fail:"UPPERCASE_WITH_UNDERSCORES" "docs: a lowercase file name is refused" scripts/check-docs.sh docs-name
expect fail:"not named in CLAUDE.md" "docs: an orphaned doc is refused" scripts/check-docs.sh docs-orphan
expect fail:"does not exist" "docs: a dead path is refused" scripts/check-docs.sh docs-dead
expect fail:"no docs directory" "docs: a missing tree is an error, not a pass" scripts/check-docs.sh docs-missing

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
    ("forks must be skipped, however the condition is written", "github.event.pull_request.head.repo.full_name == github.repository &&", "(github.event.pull_request.head.repo.full_name == github.repository || true) &&", "plan: the condition"),
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

exit "$failed"
