# Bootstrap: management account, Organization and SSO

One-time, manual setup of the AWS **Organization management account**, the local Terraform tooling and the `bootstrap/` stack. The root user is used **only** for section 2 and afterwards only as break-glass.

Values written `<like-this>` are real values that must **not** be committed (see `CLAUDE.md`). They live in your local `~/.aws/config`, in GitHub Environment variables, or in the password manager.

| Setting | Value |
|---|---|
| Region | `<region>`. **Choose it for the data-residency guarantees you need**: this is the critical decision, and it is hard to change later (Identity Center home region, region-restricting SCPs). If it is an opt-in region, enable it in step 2.3. |
| Monthly budget | **Test budget** for this proof of concept: 20 USD, named `Workforce Budget`, alerts at 50 / 80 / 100 % of actual cost. Size your own. |
| Identity Center home region | `<region>` |

## 1. Local toolchain

No Homebrew is required. Download each release binary and put it on your `PATH` (for example `~/.local/bin`). Versions used, so updates are explicit:

| Tool | Version | Verification done |
|---|---|---|
| terraform | 1.16.4 | SHA256 against the vendor `SHA256SUMS` |
| tflint | 0.64.0 | SHA256 against the release `checksums.txt` |
| trivy | 0.74.0 | SHA256 against the release checksums file |
| aws-cli | 2.37.5 | Apple notarization and Developer ID signature |
| ruby | any (macOS and the CI runners ship it) | used by `scripts/check-workflow.sh` to parse the workflow |
| actionlint | 1.7.12 | SHA256 against the release `checksums.txt` (CI pins the linux checksum) |
| node | 24.21.0 (same as the `workforce-images` base image) | darwin-x64 tarball SHA256 against nodejs.org `SHASUMS256.txt`. Its GPG signature was **not** checked |
| uv | 0.12.20 | SHA256 against the `.sha256` file of the astral-sh release |
| pre-commit | 4.6.2 | installed with `--require-hashes --no-deps --only-binary :all:`, then `uv pip check` clean |
| lima | 2.2.0 | SHA256 against the release `SHA256SUMS`. The GPG signature (`SHA256SUMS.asc`) was **not** checked |
| colima | 0.10.3 | SHA256 against the release `.sha256sum` |
| devcontainer CLI | 0.89.0 (`@devcontainers/cli`) | npm's registry integrity check only, no separate checksum or signature was verified. Installed with `npm install -g --prefix ~/.local @devcontainers/cli@0.89.0`, since the default global prefix is not user-writable |
| docker CLI | 29.8.1 (static build) | **None**: download.docker.com publishes no checksum, so it was fetched over HTTPS only |

Check the checksum, ignoring the other platforms listed in the file:

```sh
shasum -a 256 -c --ignore-missing <checksums-file>
```

A checksum downloaded from the same place as the binary proves integrity, not who published it. Where the vendor signs its checksums (for example Terraform's GPG-signed `SHA256SUMS`), verify the signature too. This bootstrap was done with checksums only.

**Prerequisites** (install them however suits your machine):

- `git`, `gh` and the AWS CLI, with a `gh` login and an SSO session (section 3)
- `terraform`, `tflint`, `trivy` and `actionlint`, which `make check` runs
- `ruby`, which `scripts/check-workflow.sh` uses
- `node` and `uv` for the testbed and the Python tooling
- `pre-commit`, installed from the hash-pinned `images/base/requirements/pre-commit.txt` in `workforce-images` where you can (`--require-hashes`). That file pins Linux wheels, so on macOS the `pyyaml` hash has to be replaced by the one of the matching macOS wheel from PyPI
- a container runtime with the `docker` CLI, for image builds and devcontainers (on macOS, for example Colima with Lima)
- the `devcontainer` CLI, to open a repo in its devcontainer from a terminal (`devcontainer up --workspace-folder .`, then `devcontainer exec --workspace-folder . <cmd>`) without VS Code. It is installed from npm, so it needs `node`

Hints for macOS: a package manager such as Homebrew or plain release binaries both work. Put binaries somewhere on your `PATH`, prefer a user-owned directory over `/usr/local`, and check each download against the vendor checksum as above. Verify the container runtime with `docker run --rm hello-world`.

**Tested on:** an Intel Mac (x86_64), macOS 13, with the versions in the table. This is what was verified, not a required setup.

**AWS CLI v2 (macOS)** has no published checksum and no usable detached signature. Verify the installer instead:

```sh
pkgutil --check-signature AWSCLIV2.pkg   # notarized, Developer ID Installer
spctl --assess --type install -vv AWSCLIV2.pkg   # accepted, source=Notarized Developer ID
```

Both showed the signer `AMZN Mobile LLC` at the time. To install without `sudo`, extract the package (`pkgutil --expand-full`, which works on macOS 13 although it is missing from `--help`), copy `<dir>/aws-cli.pkg/Payload/aws-cli/` to `~/.local/aws-cli`, and **symlink** `aws` and `aws_completer` from it into `~/.local/bin`. Do not copy the binary alone: it depends on its sibling files.

## 2. Root user (console, once)

Sign in as root, then:

1. **Enable MFA** on root (Security credentials). Register a **second** MFA device as the recovery path, and secure the root email mailbox with MFA too, since it is the password-reset channel.
2. **Account → IAM user and role access to Billing information → Activate IAM Access.**
3. **Account → AWS Regions:** enable `<region>` if it is an opt-in region. Do not disable it later: it would break SSO. Set the alternate contacts (security, billing) on the same page.
4. **Budgets:** create a monthly **test** cost budget named `Workforce Budget`: 20 USD, recurring, fixed, alerts at 50, 80 and 100 % of actual cost by email.
5. **AWS Organizations → Create an organization** with **All features** (cannot be downgraded). Click the verification link AWS emails to the root address.
6. **IAM Identity Center:** first switch the console region to `<region>`, then click Enable. The home region cannot be moved without deleting the instance, which loses every user, permission set and assignment. Enable it with AWS Organizations, then
   - create your user,
   - require MFA at every sign-in (Settings → Authentication),
   - create the `AdministratorAccess` permission set,
   - assign it to your user on the management account,
   - accept the invite and register MFA.
7. **Sign out of root** and store its credentials offline. Never create root access keys. Root is the break-glass account if Identity Center or `<region>` is unavailable.

## 3. SSO profile (local only)

`~/.aws/config`:

```ini
[sso-session workforce]
sso_start_url = <access-portal-url>
sso_region = <region>
sso_registration_scopes = sso:account:access

[profile workforce-management]
sso_session = workforce
sso_account_id = <management-account-id>
sso_role_name = AdministratorAccess
region = <region>
```

Log in with `aws sso login --sso-session workforce` (the token expires, so repeat it when the CLI reports `Token has expired`). The callback is on `127.0.0.1`, so the browser must run on the same machine. On a headless or remote machine use `aws sso login --sso-session workforce --use-device-code` instead and open the printed URL on any device.

Confirm the login with `AWS_PROFILE=workforce-management aws sts get-caller-identity --query Arn --output text` (the full output includes the account ID, so do not paste it into issues or PRs). It prints an assumed `AWSReservedSSO_AdministratorAccess` role ARN.

## 4. Verify

Run with `AWS_PROFILE=workforce-management` and `ACCT=$(aws sts get-caller-identity --query Account --output text)`.

```sh
# Not root: the ARN is an assumed AWSReservedSSO_AdministratorAccess role
aws sts get-caller-identity --query Arn --output text

# Organization exists with all features: prints ALL
aws organizations describe-organization --query Organization.FeatureSet --output text

# Root MFA is on: prints 1
aws iam get-account-summary --query SummaryMap.AccountMFAEnabled --output text

# No root access keys: prints 0
aws iam get-account-summary --query SummaryMap.AccountAccessKeysPresent --output text

# Region is enabled: prints ENABLED
aws account get-region-opt-status --region-name <region> --query RegionOptStatus --output text

# Budget exists: prints "Workforce Budget  20.0  USD  MONTHLY"
aws budgets describe-budgets --account-id "$ACCT" \
  --query 'Budgets[].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit,TimeUnit]' --output text

# Alerts: prints ACTUAL with 50.0, 80.0 and 100.0 (in any order)
aws budgets describe-notifications-for-budget --account-id "$ACCT" --budget-name "Workforce Budget" \
  --query 'Notifications[].[NotificationType,Threshold]' --output text

# Each alert has an email subscriber (repeat with 50, 80, 100): prints EMAIL
aws budgets describe-subscribers-for-notification --account-id "$ACCT" --budget-name "Workforce Budget" \
  --notification '{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"}' \
  --query 'Subscribers[].SubscriptionType' --output text
```

Verified in the console only, with no CLI check: IAM access to Billing (step 2.2), always-on Identity Center MFA (step 2.6) and the second root MFA device.

## 5. Terraform tooling

The Terraform version is pinned in `.terraform-version` (CI reads it too), so update it there when bumping. Every stack and module declares a `required_version` of at least `>= 1.9` (`bootstrap/` uses `>= 1.10`, which the S3 lockfile needs) and pins the AWS provider to `~> 6`. `make versions` checks those values (a text match, so keep each constraint on one line), and tflint checks that constraints exist at all. Each stack that declares providers must also be listed in the terraform block of `.github/dependabot.yml` (`make dependabot`). Directories are discovered by `scripts/stacks.sh`: `bootstrap/`, `live/**` and `modules/**` (`tests/` directories are skipped).

```sh
make fmt        # terraform fmt -check
make validate   # per directory: init -backend=false, then validate
make lint       # tflint (installs the pinned AWS ruleset on first run)
make versions   # required_version >= 1.9 and AWS ~> 6
make dependabot # every stack with providers is in dependabot.yml
make sec        # trivy config, HIGH and CRITICAL fail
make test       # terraform test, in directories that have *.tftest.hcl files
make workflows  # actionlint and the structure checks of the Terraform workflow
make selftest   # proves the gates above pass on valid code and fail on broken code
make check      # all of the above
```

CI runs the same targets as separate jobs (`tf-test` runs `make test`), so a local `make check` predicts CI. The loops live in `scripts/each.sh` and stop at the first error, because macOS ships Make 3.81, which cannot do that from a recipe.

## 6. Bootstrap stack (Terraform, applied once locally)

`bootstrap/` creates the Terraform state bucket, the GitHub OIDC provider and two roles, `github-infra-management` and `github-infra-management-plan`, in the management account. It is applied from a laptop once. Its own state lives in the bucket it creates, so the first apply uses local state, which is then migrated.

What it creates:

- **State bucket:** versioned, encrypted at rest (SSE-S3), all public access blocked, ACLs disabled, TLS-only bucket policy, old versions expire after 90 days (the newest 10 are always kept), `prevent_destroy`. The name is random-suffixed and passed in, never derived from an account ID.
- **OIDC provider** for `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
- **Role `github-infra-management`:** assumable only by the subject `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:management` (an exact `StringEquals`, no wildcard). This repository issues **immutable subjects** with numeric IDs, which the defaults in `variables.tf` carry; check the format with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`. Permissions: list the state bucket, read the bootstrap state, lock and unlock its lockfile, and read the resources of this stack.

- **Role `github-infra-management-plan`:** read-only, for plans on pull requests. It can be assumed only by the subject `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:management-plan`. It lists the bucket, reads the object `bootstrap/terraform.tfstate` (no other stack) and reads the bootstrap resources, with S3 and IAM `Get` and `List` actions only. It has no lockfile access, so plans that use it must run with `-lock=false`.

The only guard on the `github-infra-management` role is the protection of the `management` GitHub Environment: anyone who can push a workflow to the repository could otherwise create an unprotected environment of that name and obtain a token. The GitHub App that authors commits (`buzzl-workforce-agent`) must therefore have neither the Administration nor the Environments write permission, or it could weaken that protection.

### Step 0: protect the `management` environment (maintainer, before the apply)

```sh
gh api -X PUT repos/BuzzL/workforce-infra/environments/management --input - <<'JSON'
{"reviewers":[{"type":"User","id":6116516}],"prevent_self_review":false,"can_admins_bypass":false,
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
JSON
gh api -X POST repos/BuzzL/workforce-infra/environments/management/deployment-branch-policies -f name=main -f type=branch

# Verify: one required reviewer, no admin bypass, only main may deploy
gh api repos/BuzzL/workforce-infra/environments/management --jq '{reviewers: [.protection_rules[] | select(.type=="required_reviewers") | .reviewers[].reviewer.login], can_admins_bypass, deployment_branch_policy}'
gh api repos/BuzzL/workforce-infra/environments/management/deployment-branch-policies --jq '.branch_policies[].name'
```

`prevent_self_review` is `false` because the maintainer is the only reviewer. If `can_admins_bypass` is still `true`, turn off "Allow administrators to bypass configured protection rules" in the environment's settings.

### Step 0b: the `management-plan` environment (maintainer)

This environment has **no reviewer and accepts any branch**, on purpose: pull requests must be able to plan. What limits it is the role behind it, which is read-only. Anyone who can push a branch to the repository can run code with that role's reads, so the role must never gain a write action.

```sh
gh api -X PUT repos/BuzzL/workforce-infra/environments/management-plan
```

### Apply

Values in `<...>` stay local; the files below are gitignored.

```sh
export AWS_PROFILE=workforce-management
cd bootstrap

# 1. Choose the bucket name and write the local files.
BUCKET="workforce-tfstate-$(openssl rand -hex 4)"
cp terraform.tfvars.example terraform.tfvars   # set region and state_bucket_name=$BUCKET
cp backend.hcl.example backend.hcl             # set bucket=$BUCKET and region

# 2. First apply with local state: an override file swaps the S3 backend for a local one.
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
terraform init
terraform plan -out=bootstrap.tfplan           # read it
terraform apply bootstrap.tfplan

# 3. Migrate the state into the bucket (answer yes to copying it), and check it is there
#    and that nothing is left to change before the local copy is removed.
rm backend_override.tf
terraform init -migrate-state -backend-config=backend.hcl
terraform plan -detailed-exitcode \
  && aws s3 ls "s3://$BUCKET/bootstrap/terraform.tfstate" \
  && rm -f terraform.tfstate terraform.tfstate.backup bootstrap.tfplan
```

If the migration fails, the local `terraform.tfstate` is still there: fix the cause and run `init -migrate-state` again. The plan file and the state hold account IDs, which is why `*.tfplan`, `*.tfstate*` and `*_override.tf` are gitignored.

### Verify

`$BUCKET` is the bucket name; the roles are `github-infra-management` and `github-infra-management-plan`.

```sh
aws s3api get-bucket-versioning --bucket "$BUCKET" --query Status --output text             # Enabled
aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text   # AES256
aws s3api get-public-access-block --bucket "$BUCKET" --query 'PublicAccessBlockConfiguration' --output text   # True x4
aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text                 # Deny aws:SecureTransport=false
aws iam get-role --role-name github-infra-management --query 'Role.AssumeRolePolicyDocument' # exact sub, StringEquals
aws iam get-role --role-name github-infra-management-plan --query 'Role.AssumeRolePolicyDocument' # exact sub (…:environment:management-plan), StringEquals
aws s3 ls "s3://$BUCKET/bootstrap/"                                                          # terraform.tfstate
```

Keep the role ARNs and the bucket name out of the repository. `scripts/set-environment-secrets.sh` (idempotent) reads them from the outputs of `bootstrap/` and from IAM, validates them, sets the secrets `AWS_ROLE_ARN`, `AWS_ROLE_ID` and `STATE_BUCKET` of the `management` and `management-plan` environments without printing them, and deletes the variables of the same names (`--check` lists names only).

### Change an applied bootstrap

`backend.hcl` and `terraform.tfvars` stay in `bootstrap/`, and the state is in the bucket. Change the code through a PR, and apply locally from the merged `main`:

```sh
export AWS_PROFILE=workforce-management
git switch main && git pull --ff-only
cd bootstrap
terraform init -backend-config=backend.hcl
terraform plan -out=bootstrap.tfplan        # read it
terraform apply bootstrap.tfplan
terraform plan -detailed-exitcode           # 0: nothing left to change
rm -f bootstrap.tfplan
```

Keep the role ARN and the bucket name out of the repository.

## 7. CI: Terraform workflow

`.github/workflows/terraform.yml` runs when a pull request or a push to `main` touches Terraform files (`bootstrap/`, `live/`, `modules/`, `.terraform-version`, the stack scripts or the workflow itself). Stacks are discovered by `scripts/ci-stacks.sh`, which limits stack names to `[a-z0-9/_-]`, derives the GitHub Environments from the path and fails on a path or an environment it does not know (`test`, `qa` and `demo` are the only environment stacks).

| Stack | Applied by CI | Environment after a merge | Environment for the plan on a PR |
|---|---|---|---|
| `bootstrap` | no, applied locally (section 6) | `management` | `management-plan` |
| `live/management` | yes | `management` | `management-plan` |
| `live/environments/test`, `.../qa`, `.../demo` | yes | the same name | none |

The `management` role can currently only manage its own state and read the bootstrap resources: a stack that needs more permissions gets them in `bootstrap/ci_role.tf`, applied locally. The GitHub Environments `test`, `qa` and `demo` do not exist. GitHub creates a referenced environment without any protection on its first use, so each one must be created with a required reviewer before its stack is added.

- **Pull requests:** a plan job per stack with a plan environment, through the read-only role of `management-plan`, with `-lock=false`. The job runs the code of the pull request, so it has no `pull-requests` permission. A separate `comment` job with no AWS credentials and no environment checks out `scripts/redact.sh` only and posts the plan as a PR comment for the commit, updated in place. Pull requests from forks are skipped: they get no OIDC token.
- **After a merge to `main`:** one job per stack waits for the required reviewer of its environment, then plans and applies exactly that plan when it has changes. The approval is given before the plan exists, so the reviewer relies on the plan shown on the pull request. `bootstrap/` is plan only: a plan with changes fails the job, so approve its job after the local apply.
- **Authentication:** GitHub OIDC only, no stored keys. `AWS_ROLE_ARN`, `AWS_ROLE_ID` and `STATE_BUCKET` are **secrets** of each GitHub Environment (`management`, `management-plan`), set by `scripts/set-environment-secrets.sh`. `AWS_REGION` is a variable. `AWS_ROLE_ID` is the role's unique ID: the credentials action prints it, and it decodes to the account ID, so it is referenced in the job `env:` only to be masked.
- **This repository is public, so logs, artifacts and comments are too.** A secret is masked everywhere in the logs, including in the step headers that print an action's inputs, which a variable is not. Masking prevents accidents only: any branch of this repository can print a secret of `management-plan` in encoded form. Terraform output is never printed raw: `scripts/redact.sh` replaces 12-digit numbers, the state bucket name, AWS unique IDs and email addresses before the output reaches a log or the plan artifact, and the comment job redacts it again, treating the artifact as untrusted. Only a header of the expected shape is printed outside the code fence, lines that could close the fence are dropped and the size is capped. The comment keeps its edit history, so a redaction miss stays visible until the comment is deleted.
- **No expression in scripts:** values reach shell scripts through `env:`, never through `${{ }}` in a `run:` block. Every action is pinned by commit SHA.
- **State key** of a stack: `<stack>/terraform.tfstate`. The plan role can read only `bootstrap/terraform.tfstate`, so a plan of another stack needs its read access to be added to `bootstrap/plan_role.tf` first.
- **Concurrency:** one apply per stack at a time, stacks apply one after the other, a newer push cancels the older plan of a pull request.
- **Checks of the workflow:** `actionlint` and `scripts/check-workflow.sh` (`make workflows`, needs Ruby) parse the workflow and compare each job with an exact allowlist: permissions, conditions, environments, actions and pins, contexts (the only variable is `AWS_REGION`), secrets, masking, and that every Terraform call goes through the redaction. `make selftest` proves each check rejects the matching bad change and that the redaction hides what it must.
- An `AccessDenied` in a plan means the role lacks a read permission for a resource of the stack: add it in `bootstrap/` and apply locally.
