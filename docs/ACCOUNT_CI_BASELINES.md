# Account CI baselines

## Context

CI manages the AWS accounts without long-lived keys: GitHub Actions presents an OIDC token and assumes a role. The management account has had this since `bootstrap/`. Every new member account (`security`, `workforce`) needs the same baseline before CI can touch it: a GitHub OIDC provider and the CI roles. The baseline is `modules/account-ci-baseline`. It is its own stack per account, `bootstrap/accounts/security` and `bootstrap/accounts/workforce`, applied locally like `bootstrap/` is for the management account. Everything else in an account is the account's own stack, `live/accounts/<account>`. Two stacks, because the role CI applies with must not be defined in the stack it applies (decision 2).

## Decisions

### 1. Two roles per account, one per GitHub Environment

| Role | Trusted environment | Can do |
|---|---|---|
| `github-infra-<account>` | `<account>` | read and write the state of its own stack and its lockfile, read the baseline resources |
| `github-infra-<account>-plan` | `<account>-plan` | read the state object of its own stack and the baseline resources, nothing else |

Both trust the provider of their account for one exact subject, `repo:<owner>@<owner id>/workforce-infra@<repo id>:environment:<environment>`, with `StringEquals` on `sub` and `aud`. The plan environment has no reviewer and accepts any branch, so its role is read-only and cannot take the lock (plans run with `-lock=false`), like `management-plan`.

Rejected: a single role that also plans pull requests. Code from any branch would then run with write access.

### 2. CI cannot change the baseline

The apply role has no IAM write permission, and it does not need one: the baseline is its own stack under `bootstrap/accounts/`, applied locally, so whatever CI is allowed to write in the account's own stack, `live/accounts/<account>`, it cannot reach its own roles. CI plans the baseline stack (drift check) through the `-plan` role and never applies it (`apply: false` in `scripts/ci-stacks.sh`). Account permissions that CI needs are added to the module in a reviewed PR and applied locally from the baseline stack.

Rejected: letting CI apply its own baseline. It needs `iam:PutRolePolicy` on its own role, which is a privilege-escalation path.

### 3. State stays in the management bucket

One bucket, one key per stack: the key CI derives from the stack path. The apply role reaches `live/accounts/<account>/terraform.tfstate` (and its `.tflock`) only. Both roles read `bootstrap/accounts/<account>/terraform.tfstate`, the state of the baseline stack, and the apply role takes its lock (the job after a merge plans the stack as a drift check), but neither can write it: it is written locally with the maintainer's own credentials, so CI cannot change its own role. The bucket policy in `bootstrap/` names those roles, one exact ARN per Allow and no wildcard. It is driven by the local variable `member_account_ids`, empty until the account's stack exists: S3 rejects a policy that names a principal that is not there yet.

Rejected: a bucket per account, which needs a second bootstrap for every account and splits the state.

### 4. A stack joins CI when it can pass

`scripts/ci-stacks.sh` ignores `bootstrap/accounts/<account>` and `live/accounts/<account>` until the stack's own `.ci-enabled` is committed. Commit it after steps 1 to 4 below: before that, a plan could only fail.

## Bootstrap, once per account

Run by the maintainer, locally, with the management admin session. The account ID is read from the management stack outputs and never committed.

0. **Enable the region in the account first, if it is not enabled by default.** Regions launched after March 2019 are opt-in and are enabled per account, so the region of this repository (`<region>`, `docs/ORGANIZATION_INPUTS.md`) must be enabled in every member account the same way. Skip this step for a region that is enabled by default. Until it is enabled, the provider's regional STS call is refused, and `terraform plan` fails with `AccessDenied` on `sts:AssumeRole` into `OrganizationAccountAccessRole`, although switching role in the console works (the console uses the global endpoint). From the management SSO admin session, switch role into the account (`OrganizationAccountAccessRole`), open Account → AWS Regions and enable `<region>`; it can take a few minutes. It cannot be done from the CLI of the management account without enabling trusted access for AWS Account Management in the Organization, which this repository does not do. Check it with:

   ```sh
   aws sts assume-role --region <region> --role-arn arn:aws:iam::<account-id>:role/OrganizationAccountAccessRole \
     --role-session-name check --query 'Credentials.Expiration' --output text   # prints a timestamp
   ```

1. Fill `bootstrap/accounts/<account>/backend.hcl` and `terraform.tfvars` from the `.example` files, with `break_glass_account_id` set.
2. `terraform init -backend-config=backend.hcl && terraform plan`, review, then `terraform apply`. The provider assumes `OrganizationAccountAccessRole` in the account, the state is written with your own credentials.
3. Remove `break_glass_account_id` from `terraform.tfvars`: from now on the stack is applied locally with the maintainer's own administrator session in the account (the provider, `AWS_PROFILE=<account profile>`) and the state backend on the management session (`profile` in `backend.hcl`), never as the CI role. Then add the account to `member_account_ids` in `bootstrap/terraform.tfvars` and in the secret `MEMBER_ACCOUNT_IDS` of `management` and `management-plan` (`MEMBER_ACCOUNT_IDS='{"security":"<id>"}' scripts/set-environment-secrets.sh`; CI plans `bootstrap/` too and would otherwise see the grants as drift), and apply `bootstrap/` locally: this opens the state bucket to the new roles and lets the management CI role assume the break-glass role there.
4. `scripts/set-account-environment-secrets.sh <account>` creates the GitHub Environments `<account>` (protected: the maintainer as required reviewer, no admin bypass, `main` only) and `<account>-plan` (no reviewer, any branch, read-only role) with the secrets `AWS_ROLE_ARN`, `AWS_ROLE_ID`, `STATE_BUCKET` and the variable `AWS_REGION`. The `security` environments also get `MAINTAINER_USERNAME` and `ASSIGNMENT_ACCOUNT_IDS` (`docs/IDENTITY_CENTER.md`). The role ARN and ID are secrets so that they are masked in public logs.
5. Commit `bootstrap/accounts/<account>/.ci-enabled` and `live/accounts/<account>/.ci-enabled`. The next PR plans the stack through OIDC, which must be a no-op.

## Moving an existing baseline, once

`security` and `workforce` were bootstrapped when their baseline lived in `live/accounts/<account>`. The move to `bootstrap/accounts/<account>` adopts the same resources without recreating them: `bootstrap/accounts/<account>/imports.tf` has an `import` block per resource. `security` keeps a stack in `live/accounts/security` (Identity Center and the audit log bucket), which drops the baseline from its state with a `removed` block. `workforce` owns no resources of its own yet, so its `live/accounts/workforce` stack is deleted; its old state is emptied by hand. Run by the maintainer, locally, per account, **from the pull request branch, before the merge**, after the pull request is approved and with an explicit yes for each step:

1. `bootstrap/`: apply, so that both roles may read the baseline state and the apply role may lock it (`bootstrap/state_bucket.tf`).
2. `bootstrap/accounts/<account>`: fill `backend.hcl` and `terraform.tfvars` (for `security`, set `audit_log_bucket_name` to the value of the secret `AUDIT_LOG_BUCKET` when audit logging is on, or the roles lose their read of the bucket), `terraform init -backend-config=backend.hcl`, then `terraform plan`. It must read **11 to import, 0 to add, 5 to change, 0 to destroy**, and nothing may be replaced. The 5 changes are the expected ones: the `Stack` tag of the OIDC provider and of the two roles (now `bootstrap/accounts/<account>`), and the two inline state policies, `terraform-state` of the apply role and `terraform-state-read` of the plan role, which gain the baseline state key. In the diff of `baseline-read` (security), `ReadAuditLogBucket` must still be there. Any add, destroy, replace or other change stops the move. Apply.
3. `security`: in `live/accounts/security`, `terraform plan` must read only that the resources are removed from the state and **0 to destroy**. Apply.
   `workforce`: from the checkout of `main`, where `live/accounts/workforce` still exists, `terraform state rm module.baseline`. The state is versioned, so the previous version is the way back.
4. Both baseline stacks and `live/accounts/security` plan clean. Commit the `.ci-enabled` markers of `bootstrap/accounts/<account>`; the next pull request plans them through OIDC, which must be a no-op.
5. **Do not merge before step 3.** After the merge the post-merge job fails for a stack that CI does not apply when its plan has changes, and the plan of `live/accounts/security` has the removals until step 3 is applied.
6. In a later change, remove `imports.tf` and the `removed` block: they have no effect after the first apply. `live/accounts/workforce` returns when the account owns resources.

If step 2 shows a destroy or an add, do not apply: the baseline in the account differs from the module, which is a finding to understand first.

## Break-glass

`OrganizationAccountAccessRole` is created by Organizations in each member account with full administrator access, trusted by the management account. It is **break-glass only**:

- Allowed uses: the one-time bootstrap above, and recovery when the CI roles or the OIDC provider are broken or deleted.
- Not allowed: routine changes, anything CI can do, or any use by an agent.
- Who: the maintainer, from the management admin session, or the management CI role (the maintainer approved this for the bootstrap). The CI role may assume it only into the accounts in `member_account_ids` and only with the session name `baseline-bootstrap`, which the stacks use, so its use stands out in CloudTrail. The permission exists only once an account is listed.
- Every use is recorded as an `AssumeRole` event in CloudTrail once the organization trail exists; after a use, write down why in the Linear issue.
- If a use is not the maintainer's, treat it as an incident and rotate.

- The session name is chosen by the caller, so `baseline-bootstrap` is a way to spot a use in CloudTrail, not a control. The control is the `management` environment protection. The permission stays for as long as an account is in `member_account_ids`; to take it away, remove the account there and re-apply (its state access goes too).
- If a CI role is deleted and recreated, the bucket policy stops matching it (AWS stores role principals by ID): re-apply `bootstrap/` after recreating a role.

Rejected: removing the role. It is the only way back into an account whose OIDC provider was deleted. Closing that door is not worth the lockout.
