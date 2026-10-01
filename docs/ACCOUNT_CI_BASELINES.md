# Account CI baselines

## Context

CI manages the AWS accounts without long-lived keys: GitHub Actions presents an OIDC token and assumes a role. The management account has had this since `bootstrap/`. Every new member account (`security`, `workforce`) needs the same baseline before CI can touch it: a GitHub OIDC provider and the CI roles. The baseline is `modules/account-ci-baseline`, used by `live/accounts/security` and `live/accounts/workforce`.

## Decisions

### 1. Two roles per account, one per GitHub Environment

| Role | Trusted environment | Can do |
|---|---|---|
| `github-infra-<account>` | `<account>` | read and write the state of its own stack and its lockfile, read the baseline resources |
| `github-infra-<account>-plan` | `<account>-plan` | read the state object of its own stack and the baseline resources, nothing else |

Both trust the provider of their account for one exact subject, `repo:<owner>@<owner id>/workforce-infra@<repo id>:environment:<environment>`, with `StringEquals` on `sub` and `aud`. The plan environment has no reviewer and accepts any branch, so its role is read-only and cannot take the lock (plans run with `-lock=false`), like `management-plan`.

Rejected: a single role that also plans pull requests. Code from any branch would then run with write access.

### 2. CI cannot change the baseline

The apply role has no IAM write permission. The baseline is applied locally, once, and changed locally, so CI cannot widen its own permissions. CI plans the stacks (drift check) and never applies them (`apply: false` in `scripts/ci-stacks.sh`). Account permissions that CI really needs are added to the module in a reviewed PR and applied locally.

Rejected: letting CI apply its own baseline. It needs `iam:PutRolePolicy` on its own role, which is a privilege-escalation path.

### 3. State stays in the management bucket

One bucket, one key per stack: `live/accounts/<account>/terraform.tfstate`, the key CI derives from the stack path. Each role reaches its own key (and `.tflock` for the apply role) only. The bucket policy in `bootstrap/` names those roles, one exact ARN per Allow and no wildcard (approved by the maintainer for IAT-32). It is driven by the local variable `member_account_ids`, empty until the account's stack exists: S3 rejects a policy that names a principal that is not there yet.

Rejected: a bucket per account, which needs a second bootstrap for every account and splits the state.

### 4. A stack joins CI when it can pass

`scripts/ci-stacks.sh` ignores `live/accounts/<account>` until `live/accounts/<account>/.ci-enabled` is committed. Commit it after steps 1 to 4 below: before that, a plan could only fail.

## Bootstrap, once per account

Run by the maintainer, locally, with the management admin session. The account ID is read from the management stack outputs and never committed.

1. Fill `live/accounts/<account>/backend.hcl` and `terraform.tfvars` from the `.example` files, with `break_glass_account_id` set.
2. `terraform init -backend-config=backend.hcl && terraform plan`, review, then `terraform apply`. The provider assumes `OrganizationAccountAccessRole` in the account, the state is written with your own credentials.
3. Remove `break_glass_account_id` from `terraform.tfvars`: from now on the stack is applied as the account's own role or not at all. Then add the account to `member_account_ids` in `bootstrap/terraform.tfvars` and apply `bootstrap/` locally: this opens the state bucket to the new roles and lets the management CI role assume the break-glass role there.
4. `scripts/set-account-environment-secrets.sh <account>` creates the GitHub Environments `<account>` and `<account>-plan` with the secrets `AWS_ROLE_ARN`, `AWS_ROLE_ID`, `STATE_BUCKET` and the variable `AWS_REGION`. The role ARN and ID are secrets so that they are masked in public logs.
5. Commit `live/accounts/<account>/.ci-enabled`. The next PR plans the stack through OIDC, which must be a no-op.

## Break-glass

`OrganizationAccountAccessRole` is created by Organizations in each member account with full administrator access, trusted by the management account. It is **break-glass only**:

- Allowed uses: the one-time bootstrap above, and recovery when the CI roles or the OIDC provider are broken or deleted.
- Not allowed: routine changes, anything CI can do, or any use by an agent.
- Who: the maintainer, from the management admin session, or the management CI role (the maintainer approved this for the bootstrap). The CI role may assume it only into the accounts in `member_account_ids` and only with the session name `baseline-bootstrap`, which the stacks use, so its use stands out in CloudTrail. The permission exists only once an account is listed.
- Every use is recorded as an `AssumeRole` event in CloudTrail (IAT-34); after a use, write down why in the Linear issue.
- If a use is not the maintainer's, treat it as an incident and rotate.

Rejected: removing the role. It is the only way back into an account whose OIDC provider was deleted. Closing that door is not worth the lockout.
