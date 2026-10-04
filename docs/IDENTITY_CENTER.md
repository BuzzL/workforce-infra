# Identity Center

## Context

One door for human access: SSO with MFA into every account, administered from `security`. The instance lives in the management account (home region: see `docs/ORGANIZATION_INPUTS.md`) and was enabled by hand in `docs/BOOTSTRAP.md` step 2.6, with the maintainer user and a first `AdministratorAccess` permission set assigned on the management account.

## Decisions

### 1. Administration is delegated to `security`

`bootstrap/identity.tf` registers `security` as delegated administrator of `sso.amazonaws.com`. It sits in `bootstrap/` (applied locally with SSO admin), not in `live/management`, so no CI role can change who administers access: the CI roles only get `organizations:ListDelegatedAdministrators`, asserted literally in `bootstrap/tests`. It exists once `security` is in `member_account_ids`.

**Blast radius:** an administrator of `security` can now grant themselves access on every member account. Treat `security` as the most sensitive account: only the maintainer is assigned there, `OrganizationAccountAccessRole` in it is break-glass (`docs/ACCOUNT_CI_BASELINES.md`), and every use is written down in Linear. An SCP that protects the Identity Center administration in `security` is a possible follow-up and needs the maintainer's explicit approval first (`CLAUDE.md`).

Permission sets and assignments live in `live/accounts/security` (`identity.tf`, module `modules/identity-center-access`).

### 2. Two permission sets of their own, one AWS managed policy each

| Permission set | Policy | Session |
|---|---|---|
| `WorkforceAdministrator` | `AdministratorAccess` | 4 hours |
| `WorkforceReadOnly` | `ReadOnlyAccess` | 8 hours |

Nothing is inlined and customer managed policies are rejected, so what a set can do is readable from its name. The maintainer, the only user, gets both on every member account: use `WorkforceReadOnly` to look, `WorkforceAdministrator` to change.

The sets are **new** and do not reuse the manual `AdministratorAccess` of `docs/BOOTSTRAP.md`, which is never imported. That set is provisioned in the management account, and a delegated administrator cannot modify a set that is provisioned there: importing it would make the first apply fail on any difference (session duration, tags, policy re-provisioning). The AWS managed policies keep their names, so `get-caller-identity` shows `AWSReservedSSO_WorkforceAdministrator_*` in member accounts and `AWSReservedSSO_AdministratorAccess_*` in management.

### 3. The management account is assigned by hand

Identity Center does not let a delegated administrator provision a permission set into the management account. The maintainer's manual `AdministratorAccess` assignment there stays as it is (`docs/BOOTSTRAP.md`); add `ReadOnlyAccess` there from the management account console if wanted. This is the one account that is not Terraform managed here, and the stack refuses `management` in `assignment_account_ids`.

### 4. MFA is an Identity Center setting, not Terraform

Terraform has no resource for the sign-in MFA mode, and sessions that come from Identity Center do not carry `aws:MultiFactorAuthPresent`, so an IAM condition cannot enforce it. MFA is required at every sign-in (Settings → Authentication, `docs/BOOTSTRAP.md` step 2.6) and verified by hand; the console is the only check.

### 5. CI plans and applies, behind the maintainer's approval

`live/accounts/security` (the permission sets, their policy attachments and the assignments, and the audit log bucket) is applied by CI. A pull request gets a read-only plan, as for every stack. After the merge, the `security` job waits for the maintainer's approval on the `security` GitHub Environment (required reviewer, `main` only, no admin bypass), then plans again and applies exactly that plan.

The apply role writes only what this stack manages (`extra_write_statements` of `modules/account-ci-baseline`, defined in `bootstrap/accounts/security`, asserted literally in its tests): create and update permission sets, attach the managed policy, provision, create account assignments, and follow those requests. It does **not** delete or detach anything and has no IAM write. Removing a set, an attachment or an assignment is blocked twice: by `prevent_destroy` on each of them (`scripts/check-prevent-destroy.sh` fails the build if the line is missing), and by the absence of the delete actions. A deliberate removal is a reviewed change that deletes the `prevent_destroy` line first and a local step with SSO admin.

This is the one statement group that lets CI change **who can reach an account**: creating an assignment or changing a permission set. The control is the approval on the `security` environment, which only the maintainer gives after reading the plan, and the review of the pull request that changed the stack. The role that CI applies with cannot widen itself: the OIDC provider and the two CI roles are a separate stack, `bootstrap/accounts/security`, applied locally (`docs/ACCOUNT_CI_BASELINES.md`).

The plan reads (`sso:List*`, `sso:Describe*`, `identitystore:Describe*`) are added to both roles through the module input `extra_read_statements` and asserted in `bootstrap/accounts/security/tests`, the stack that defines the roles.

The maintainer user name and the account IDs to assign are the secrets `MAINTAINER_USERNAME` and `ASSIGNMENT_ACCOUNT_IDS` of the `security` and `security-plan` environments (`scripts/set-account-environment-secrets.sh security`).

The plan role can run from any branch and `identitystore:DescribeUser` has no resource to scope to, so branch code can read the identity store user profiles. Accepted: there is one user and pushing a branch needs write access. The plan output is redacted (`scripts/redact.sh` masks `ssoins-`/`ps-` IDs and UUIDs) before it is posted.

## What stays local

Two things are applied by the maintainer with SSO admin, because they change who can administer Identity Center or what CI may do:

1. The delegation, `bootstrap/identity.tf`: registers `security` as delegated administrator of `sso.amazonaws.com`. It is registered once and never changes. `terraform plan` of `bootstrap/` must show exactly one `aws_organizations_delegated_administrator`; apply it with the management SSO admin session. Before this, the Identity Center home region must be enabled in `security` and in every assigned account, if it is not enabled by default (`docs/ACCOUNT_CI_BASELINES.md`, step 0).
2. The baseline of the account, `bootstrap/accounts/security` (the CI roles and their permissions), when CI needs a new permission: widen the role there first, in its own pull request, and apply it locally before the pull request that needs it.

The first creation of the permission sets and assignments was applied locally, before CI could apply this stack. Adding an account to `ASSIGNMENT_ACCOUNT_IDS` is a normal change: set the secret, and the next CI run plans and applies it after the maintainer's approval.

Keep the working `AdministratorAccess` session on the management account; it is not touched. The root user is the break-glass if Identity Center is broken.

## Local SSO profiles

One profile per account in `~/.aws/config`, all on the `workforce` SSO session of `docs/BOOTSTRAP.md` section 3. Account IDs stay local:

```ini
[profile workforce-security]
sso_session = workforce
sso_account_id = <security-account-id>
sso_role_name = WorkforceAdministrator

[profile workforce-security-readonly]
sso_session = workforce
sso_account_id = <security-account-id>
sso_role_name = WorkforceReadOnly
```

The management profile keeps `sso_role_name = AdministratorAccess` (`docs/BOOTSTRAP.md`). Repeat for `workforce` and for any later account. Log in once with `aws sso login --sso-session workforce`.

## Verify

For each profile, the caller must be an assumed `AWSReservedSSO_*` role, never root:

```sh
for p in workforce-management workforce-security workforce-workforce; do
  AWS_PROFILE=$p aws sts get-caller-identity --query Arn --output text   # prints an assumed-role ARN
done

# Delegation: prints the name of the security account
AWS_PROFILE=workforce-management aws organizations list-delegated-administrators \
  --service-principal sso.amazonaws.com --query 'DelegatedAdministrators[].Name' --output text
```

Done when these are confirmed in chat for every account (IAT-33).

## Not covered

- Groups and more than one user: out of scope, there is one maintainer.
- The `test`, `quality` and `demo` accounts (M3): add them to `ASSIGNMENT_ACCOUNT_IDS` when they exist.
