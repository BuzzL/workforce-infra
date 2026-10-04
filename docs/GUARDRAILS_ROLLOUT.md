# Guardrails: the baseline SCPs and how they are attached

The four baseline service control policies (`modules/scp-baseline`) are attached to the organizational units one stage at a time. An SCP that is wrong can lock principals out, so every stage is a reviewed PR whose plan is in its comment, applied by CI only after the approval of the `management` environment, and then verified. The management account is never affected by SCPs: its access is the fallback if a member account is locked out.

## What is managed

The code is in `live/management` (`service_control_policies.tf`, `scp_attachments.tf`), applied by CI like the rest of the stack. The management CI role may create, change, tag and delete the stack's SCPs and attach and detach them on organizational units only (`bootstrap/service_control_policies.tf`). By the design of its ARN patterns (checked with the IAM policy simulator on the real ARN shapes: attach and detach are allowed on the stack's own SCPs and on OUs, denied on the root, an account and `FullAWSAccess`) it should not attach to the root or to an account, nor touch `FullAWSAccess`. The guards that count are the validation of `scp_attachments`, the OU reference and the approval of the apply.

| Object | Source | Attached to |
|---|---|---|
| `deny-leave-organization`, `deny-root-user`, `deny-disable-cloudtrail`, `deny-outside-allowed-region` | `modules/scp-baseline` | the OUs set by the default of `var.scp_attachments` |
| `DenyLeaveAndCloseAccount` | imported from a policy created by hand | the root |

- `var.scp_attachments` maps an OU name to the baseline SCPs attached to it. Only the OU names `Management`, `Environments`, `Development` and `Operations` and the four policy names are accepted; the root and accounts cannot be named. **The default is the current state**, so changing what is attached is a change of that default in `live/management/variables.tf`.
- `DenyLeaveAndCloseAccount` denies `organizations:LeaveOrganization` and `account:CloseAccount` for every member account. It is the single, fixed exception to "never attach an SCP to the root". Its deletion is blocked by `prevent_destroy`; a change of its content is guarded by the PR review and the environment approval. `FullAWSAccess`, also attached to the root, is AWS-managed and never touched.
- The management account is not subject to SCPs. Its SSO admin access, and `OrganizationAccountAccessRole` into a member account, are the fallback.

## What is attached

| OU | Accounts | Baseline SCPs attached |
|---|---|---|
| Development | `workforce` | the four |
| Environments | `test`, `quality`, `demo` once created (IAT-41), none before | the four |
| Operations | none yet | the four |
| Management | `security` | the four |
| Root | the management account is here | `DenyLeaveAndCloseAccount` and `FullAWSAccess` only |

Every OU keeps `FullAWSAccess`. AWS allows **five SCPs directly attached to an OU**: `FullAWSAccess` plus the four baseline SCPs is exactly five, so no further SCP can be attached to such an OU without removing one. `deny-leave-organization` is partly redundant with `DenyLeaveAndCloseAccount`; merging policies or dropping one is a separate decision.

## Changing what is attached

A change is one PR that edits the default of `scp_attachments`, one OU per PR, with all four SCPs. The plan comment of the PR must contain only `aws_organizations_policy_attachment.scp[...]` lines for that OU: `+` when it is attached, `-` when it is detached. Before attaching to an OU:

- `aws organizations list-accounts-for-parent` on the OU names the accounts it reaches;
- `aws organizations list-policies-for-target` on the OU shows `FullAWSAccess` attached;
- the fallback path (management SSO admin session) works.

`Management` is last in the rollout order, because `security` holds the Identity Center delegation and the audit log bucket.

## Why `security` is not locked out

- Everything `security` does runs in the allowed region (state, audit log bucket, Identity Center home region), and `sts`, `iam`, `sso`, `identitystore`, `organizations` and `account` are exempt from the region SCP, so sign-in, role assumption and the Identity Center administration are not reached by it.
- `deny-disable-cloudtrail` has no effect on `security`: it holds no trail. The Organization trail is managed from the management account, which SCPs never reach.
- `deny-root-user` blocks the root user of `security`, with no exception; centralized root recovery (`sts:AssumeRoot`, from the management account) is not matched by it.
- If anything in `security` is locked out, the management account's SSO admin session works unchanged, and so does assuming `OrganizationAccountAccessRole` into `security` from it. That role assumption is checked before an OU with an account is attached.

## Rollback

One command per policy per OU (policy IDs from the sensitive output `scp_policy_ids`, the OU ID from `aws organizations list-organizational-units-for-parent`):

```sh
aws organizations detach-policy --policy-id <policy id> --target-id <OU id> --profile <management profile>
```

Then revert the change in a PR (restore the previous default of `scp_attachments`) so that Terraform agrees: until then the next plan wants to re-attach it.

## Verification

For each OU with an account, the SCPs are verified from a principal inside that account. Output is recorded without account and organization IDs.

**Every simulator call must pass `--context-entries ContextKeyName=aws:RequestedRegion,ContextKeyValues=<allowed region>,ContextKeyType=string`.** Without it the region SCP fires on any action outside its exception list (`StringNotEquals` on a missing key is true), so even a control such as `s3:ListAllMyBuckets` looks denied and the result proves nothing.

| SCP | How it is verified |
|---|---|
| `deny-leave-organization` | **Never a real call**: if the SCP failed, the account would leave the Organization. `aws iam simulate-principal-policy` run **by a role inside the member account** (from the management account it reports an SCP-free evaluation): `OrganizationsDecisionDetail.AllowedByOrganizations` is false, and `list-policies-for-target` shows the policy attached. Limit: `DenyLeaveAndCloseAccount` also denies this action, so the simulator cannot say which policy denied it. |
| `deny-root-user` | The simulator needs a user or role as its source, so the root cannot be simulated directly: the proof passes `aws:PrincipalArn` set to the account's root ARN with `--context-entries` (the simulator honours the override), denied, and compares with a normal SSO role, allowed. No real root session is ever created, so the end-to-end effect on a real root user is not exercised. |
| `deny-disable-cloudtrail` | A harmless real call, `aws cloudtrail stop-logging --name no-such-trail-$(uuidgen)` in the allowed region, from an admin role in the account. The name must be random, **never a real trail name and never an ARN**: if the SCP were not effective, a real name would stop that trail. With the SCP the error says explicit deny in a service control policy, and names the policy; without it, `TrailNotFoundException` (the same call in the management account shows it). A caller with no cloudtrail permission gets an implicit-deny message instead, which is not the proof. |
| `deny-outside-allowed-region` | A harmless real call, `ec2 describe-regions` in another region, is denied and the error names the policy; the same call in the allowed region, `iam get-account-summary` and `sts get-caller-identity` (regional and global endpoint) succeed. |

Verified for `Development` (`workforce`) and `Management` (`security`) with the methods above, and for the CI role of `workforce` on its read path: it assumes through OIDC, reads the state in the allowed region and plans the IAM reads with no change, under the four SCPs.

For an OU with no account (`Operations`) there is no principal to call from: the verification is that the policies are attached, and their effect is unproven until the first account exists, where the account creation story runs the checks above. The accounts of `Environments` (`test`, `quality`, `demo`) are verified the same way once they exist, each from inside the account, and the run is recorded on the issue that creates them (IAT-41), not here.

### Opening a new account

- **Order: PR approval, the maintainer's explicit yes, local apply, then merge.** The management CI role has no `organizations:CreateAccount` (IAT-31), so the apply job that a merge starts would fail on the creates and keep failing on every later push to `live/**` until the accounts exist. The plan of the PR is the same before and after the merge, so the local apply comes first and the post-merge plan is then a no-op. The local apply needs the same `TF_VAR_*` values as CI (the secrets of the `management` environment), and runs with `-parallelism=1`: concurrent `CreateAccount` calls are rate limited, and a half-created account has already consumed its email.
- The region of this repository is opt-in: enable it in the account first (`docs/ACCOUNT_CI_BASELINES.md`, step 0), or the provider's regional STS call is refused.
- No step logs in as the root user of a new account. `deny-root-user` leaves it nothing it may do (no root MFA, no root contact changes). Alternate contacts go through `account:PutAlternateContact` from a role inside the account (setting them from the management account needs trusted access for AWS Account Management, which this repository does not enable), and recovery is `sts:AssumeRoot` from the management account.
- Closing a member account is `organizations:CloseAccount` from the management account, not the member-side `account:CloseAccount` that `DenyLeaveAndCloseAccount` denies. The SCP is not loosened for it.

## Limits and open points

- The region SCP exempts only the services of `global_service_prefixes`. Console panels that call services served from `us-east-1` only (Health, Trusted Advisor, parts of the console home) show access-denied messages in a member account. They are explicit denies that change nothing; a prefix is added only in the PR that needs it (`docs/ORGANIZATION_INPUTS.md`).
- The write path of a member account's CI role under the SCPs (an apply) is not exercised yet: the first apply in `workforce` is its proof.
- Bedrock cross-region inference (`eu.` and `global.` inference profiles) in `workforce` is an open risk of the region SCP, not tried yet (no model access in the account); it is settled with the model provider story. If it fails, the rollback is to detach the region SCP from `Development`, never to widen the Deny during a rollout.
