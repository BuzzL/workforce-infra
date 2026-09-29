# Bootstrap: management account, Organization and SSO

One-time, manual setup of the AWS **Organization management account**. Everything after this is Terraform applied from CI, except the `bootstrap/` stack (see the end). The root user is used **only** for section 2 and afterwards only as break-glass.

Values written `<like-this>` are real values that must **not** be committed (see `CLAUDE.md`). They live in your local `~/.aws/config`, in GitHub Environment variables, or in the password manager.

| Setting | Value |
|---|---|
| Region | `<region>`. **Choose it for the data-residency guarantees you need**: this is the critical decision, and it is hard to change later (Identity Center home region, region-restricting SCPs). Also check that Bedrock models are available there before the Bedrock work, since cross-region inference profiles may route to other regions. If it is an opt-in region, enable it in step 2.3. |
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

Check the checksum, ignoring the other platforms listed in the file:

```sh
shasum -a 256 -c --ignore-missing <checksums-file>
```

A checksum downloaded from the same place as the binary proves integrity, not who published it. Where the vendor signs its checksums (for example Terraform's GPG-signed `SHA256SUMS`), verify the signature too. This bootstrap was done with checksums only.

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
4. **Budgets:** create a monthly **test** cost budget named `Workforce Budget`: 20 USD, recurring, fixed, alerts at 50, 80 and 100 % of actual cost by email. It is imported into Terraform later.
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

Log in with `aws sso login --sso-session workforce`. The callback is on `127.0.0.1`, so the browser must run on the same machine. On a headless or remote machine use `aws sso login --sso-session workforce --use-device-code` instead and open the printed URL on any device.

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

The Terraform version is pinned in `.terraform-version` (CI reads it too), so update it there when bumping. Every stack and module declares `required_version = ">= 1.9"` and pins the AWS provider to `~> 6`. `make versions` checks those values (a text match, so keep each constraint on one line), and tflint checks that constraints exist at all. Each stack that declares providers must also be listed in the terraform block of `.github/dependabot.yml` (`make dependabot`), which is added by the PR that creates the stack. Directories are discovered by `scripts/stacks.sh`: `bootstrap/`, `live/**` and `modules/**` (`tests/` directories are skipped).

```sh
make fmt        # terraform fmt -check
make validate   # per directory: init -backend=false, then validate
make lint       # tflint (installs the pinned AWS ruleset on first run)
make versions   # required_version >= 1.9 and AWS ~> 6
make dependabot # every stack with providers is in dependabot.yml
make sec        # trivy config, HIGH and CRITICAL fail
make test       # terraform test, in directories that have *.tftest.hcl files
make selftest   # proves the gates above pass on valid code and fail on broken code
make check      # all of the above
```

CI runs the same targets as separate jobs (`tf-test` runs `make test`), so a local `make check` predicts CI. The loops live in `scripts/each.sh` and stop at the first error, because macOS ships Make 3.81, which cannot do that from a recipe. With no stack yet, every gate passes on the empty tree. The remote state bucket, the GitHub OIDC provider, the CI roles and the one-time local apply are documented here when the `bootstrap/` stack lands.

## What comes next

The Terraform stacks are added one PR at a time. The first one to touch this account is `bootstrap/` (state bucket, GitHub OIDC provider, `github-infra-management` role). It is the only stack applied locally. Centralized root access management for member accounts is added later in Terraform.
