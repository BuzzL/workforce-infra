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
write_stack live/environments/qa
write_stack live/environments/demo
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"live/environments/demo","environment":"demo","apply":true},{"stack":"live/environments/qa","environment":"qa","apply":true},{"stack":"live/environments/test","environment":"test","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks apply maps paths to environments"; else echo "FAIL ci-stacks apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plan lists only stacks with a plan environment"; else echo "FAIL ci-stacks plan mapping"; echo "$got"; failed=1; fi
# Account baselines stay out of CI until their .ci-enabled marker exists (checked above: absent), and
# then are only planned (apply false), under their own <account>-plan environment.
touch live/accounts/security/.ci-enabled
got=$(scripts/ci-stacks.sh apply)
want='[{"stack":"bootstrap","environment":"management","apply":false},{"stack":"live/accounts/security","environment":"security","apply":false},{"stack":"live/environments/demo","environment":"demo","apply":true},{"stack":"live/environments/qa","environment":"qa","apply":true},{"stack":"live/environments/test","environment":"test","apply":true},{"stack":"live/management","environment":"management","apply":true}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks enables an account baseline with its marker, without apply"; else echo "FAIL ci-stacks account apply mapping"; echo "$got"; failed=1; fi
got=$(scripts/ci-stacks.sh plan)
want='[{"stack":"bootstrap","environment":"management-plan"},{"stack":"live/accounts/security","environment":"security-plan"},{"stack":"live/management","environment":"management-plan"}]'
if [ "$got" = "$want" ]; then echo "ok   ci-stacks plans an enabled account baseline in <account>-plan"; else echo "FAIL ci-stacks account plan mapping"; echo "$got"; failed=1; fi
rm live/accounts/security/.ci-enabled
expect fail:usage "ci-stacks rejects an unknown mode" scripts/ci-stacks.sh nonsense
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
  'bucket workforce-tfstate-a1b2c3d4 and other-bucket-77' \
  'parent_id = "r-ab12" ou-ab12-cdef5678 for-r-abcd' \
  'a r-ab12 r-cd34 ou-ab12-cdef5678,ou-ab12-cdef5679 arn:aws:organizations::111122223333:ou/o-abcdefghij/ou-ab12-cdef5678' \
  'r-ab12 r-cd34,ou-ab12-cdef5678,ou-ab12-cdef5679 arn:aws:organizations::x:ou/o-abcdefghij/ou-ab12-cdef5678' \
  'contact me@example.com sub repo:BuzzL@6116516/workforce-infra@1394667495:environment:m' \
  '  ~ resource "aws_iam_role" "x" {' | STATE_BUCKET=other-bucket-77 scripts/redact.sh)
want_redacted=$(printf '%s\n' \
  'id=arn:aws:iam::<account-id>:role/x <aws-id>:GitHubActions' \
  'Assumed <aws-id> token' \
  'bucket <state-bucket> and <state-bucket>' \
  'parent_id = "<org-id>" <org-id> for-r-abcd' \
  'a <org-id> <org-id> <org-id>,<org-id> arn:aws:organizations::<account-id>:ou/<org-id>/<org-id>' \
  '<org-id> <org-id>,<org-id>,<org-id> arn:aws:organizations::x:ou/<org-id>/<org-id>' \
  'contact <email> sub repo:BuzzL@6116516/workforce-infra@1394667495:environment:m' \
  '  ~ resource "aws_iam_role" "x" {')
if [ "$redacted" = "$want_redacted" ]; then echo "ok   redact hides account IDs, unique IDs, bucket names, Organization IDs and emails only"; else echo "FAIL redact"; echo "$redacted"; failed=1; fi

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
