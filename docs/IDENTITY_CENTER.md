# Identity Center

## Context

One door for human access: SSO with MFA into every account, administered from `security`. The instance lives in the management account (home region: see `docs/ORGANIZATION_INPUTS.md`) and was enabled by hand in `docs/BOOTSTRAP.md` step 2.6, with the maintainer user and a first `AdministratorAccess` permission set assigned on the management account.

## Decisions

### 1. Administration is delegated to `security`

`bootstrap/identity.tf` registers `security` as delegated administrator of `sso.amazonaws.com`. It sits in `bootstrap/` (applied locally with SSO admin), not in `live/management`, so no CI role can change who administers access: the CI roles only get `organizations:ListDelegatedAdministrators`, asserted literally in `bootstrap/tests`. It exists once `security` is in `member_account_ids`.

Permission sets and assignments live in `live/accounts/security` (`identity.tf`, module `modules/identity-center-access`).

### 2. Two permission sets, one AWS managed policy each

| Permission set | Policy | Session |
|---|---|---|
| `AdministratorAccess` | `AdministratorAccess` | 4 hours |
| `ReadOnlyAccess` | `ReadOnlyAccess` | 8 hours |

Nothing is inlined and customer managed policies are rejected, so what a set can do is readable from its name. The maintainer, the only user, gets both on every member account: use `ReadOnlyAccess` to look, `AdministratorAccess` to change.

### 3. The management account is assigned by hand

Identity Center does not let a delegated administrator provision a permission set into the management account. The maintainer's `AdministratorAccess` assignment there stays the manual one of `docs/BOOTSTRAP.md`; add `ReadOnlyAccess` there from the management account console if wanted. This is the one account that is not Terraform managed here.

### 4. MFA is an Identity Center setting, not Terraform

Terraform has no resource for the sign-in MFA mode, and sessions that come from Identity Center do not carry `aws:MultiFactorAuthPresent`, so an IAM condition cannot enforce it. MFA is required at every sign-in (Settings → Authentication, `docs/BOOTSTRAP.md` step 2.6) and verified by hand; the console is the only check.

### 5. CI plans, humans apply

As for every account baseline (`docs/ACCOUNT_CI_BASELINES.md`), CI plans the stack with a read-only role and never applies it: the CI apply role has no IAM or Identity Center write. The plan reads (`sso:List*`, `sso:Describe*`, `identitystore:Describe*`) are added to both roles through the module input `extra_read_statements` and asserted in `live/accounts/security/tests`.

The maintainer user name and the account IDs to assign are the secrets `MAINTAINER_USERNAME` and `ASSIGNMENT_ACCOUNT_IDS` of the `security` and `security-plan` environments (`scripts/set-account-environment-secrets.sh security`).

## Apply, once

Run by the maintainer, locally, in this order. Nothing here is applied by CI.

1. `bootstrap/`: with `security` in `member_account_ids`, `terraform plan` must show exactly one `aws_organizations_delegated_administrator`. Apply it with the management SSO admin session.
2. `live/accounts/security`: add `maintainer_username` and `assignment_account_ids` to `terraform.tfvars` (see the `.example`). The first run has no SSO access to `security` yet, so set `break_glass_account_id` as in `docs/ACCOUNT_CI_BASELINES.md` and remove it afterwards. Before the first apply, **import** the existing manual permission set so Terraform adopts it instead of failing on the duplicate name (`<instance-arn>` and `<permission-set-arn>` from `aws sso-admin list-instances` and `list-permission-sets`, never committed):

   ```sh
   terraform import 'module.access.aws_ssoadmin_permission_set.this["AdministratorAccess"]' '<permission-set-arn>,<instance-arn>'
   terraform plan
   ```

   Review the plan before applying: the imported set keeps its name; a session duration change from the manual one is expected. It must not remove the maintainer's assignment on the management account (that one is not in this stack).
3. `scripts/set-account-environment-secrets.sh security` with `MAINTAINER_USERNAME` and `ASSIGNMENT_ACCOUNT_IDS` in the environment, so the `security` plans can read the stack.

Keep a working `AdministratorAccess` session on the management account while doing this. The root user is the break-glass if Identity Center is broken.

## Local SSO profiles

One profile per account in `~/.aws/config`, all on the `workforce` SSO session of `docs/BOOTSTRAP.md` section 3. Account IDs stay local:

```ini
[profile workforce-security]
sso_session = workforce
sso_account_id = <security-account-id>
sso_role_name = AdministratorAccess

[profile workforce-security-readonly]
sso_session = workforce
sso_account_id = <security-account-id>
sso_role_name = ReadOnlyAccess
```

Repeat for `workforce` and for any later account. Log in once with `aws sso login --sso-session workforce`.

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
- The `test`, `qa` and `demo` accounts (M3): add them to `ASSIGNMENT_ACCOUNT_IDS` when they exist.
