# Guardrails: attaching the baseline SCPs in stages

The four baseline service control policies (`modules/scp-baseline`) are attached to the organizational units one at a time, and each attachment is proved. An SCP that is wrong can lock principals out, so every stage is a reviewed PR whose plan is in its comment, applied by CI only after the approval of the `management` environment, and then proved. The management account is never affected by SCPs: its access stays the fallback if a member account is locked out.

## What it manages

The code is in `live/management` (`service_control_policies.tf`, `scp_attachments.tf`), applied by CI like the rest of the stack. The management CI role may create, change, tag and delete the stack's SCPs and attach and detach them on organizational units only (`bootstrap/service_control_policies.tf`): by the design of its ARN patterns (checked with the IAM policy simulator on the real ARN shapes: attach and detach allowed on the stack's own SCPs and on OUs, denied on the root, an account and `FullAWSAccess`) it should not attach to the root or to an account, nor touch `FullAWSAccess`. The guards that count are the validation of `scp_attachments`, the OU reference and the approval of the apply.

| Object | Source | Attached to |
|---|---|---|
| `deny-leave-organization`, `deny-root-user`, `deny-disable-cloudtrail`, `deny-outside-allowed-region` | `modules/scp-baseline` | the OUs named in `var.scp_attachments` (nothing by default) |
| `DenyLeaveAndCloseAccount` | imported from a hand-made policy | the root, as it always was |

- `var.scp_attachments` maps an OU name to the baseline SCPs attached to it. Only the OU names `Management`, `Environments`, `Development` and `Operations` and the four policy names are accepted. The root and accounts cannot be named. **The default is the current stage**, so a stage is a change of that default in `live/management/variables.tf`.
- `DenyLeaveAndCloseAccount` denies `organizations:LeaveOrganization` and `account:CloseAccount` for every member account. It was created by hand before the stack and is the single, fixed exception to "never attach an SCP to the root". Deleting it is blocked by `prevent_destroy`; changing its content is guarded by the PR review and the environment approval. `FullAWSAccess`, also attached to the root, is AWS-managed and never touched.
- Management account: SCPs never apply to it. Its SSO admin access, and `OrganizationAccountAccessRole` into a member account, are the fallback.

## Stages

Each stage is one PR that sets `scp_attachments` for one OU, with all four SCPs. The plan comment of the PR must contain only `+ aws_organizations_policy_attachment.scp[...]` for that OU. After the merge and the approval of the apply, the proofs below are run and recorded.

| Stage | Default of `scp_attachments` | Accounts reached | Before the stage |
|---|---|---|---|
| 0 | `{}` | none | Creates the four policies and imports `DenyLeaveAndCloseAccount` and its root attachment (a plan of 2 to import, 4 to add, 2 to change, 0 to destroy: the changes are only the default tags of the imported policy and the sensitive flag of the root attachment's target, a state-only change). The four new policies have no target. |
| 1 | `Development` | `workforce` | `list-accounts-for-parent`, `list-policies-for-target` (`FullAWSAccess` still attached), the fallback path checked. |
| 2 | `Environments` | none yet | Same checks. |
| 3 | `Operations` | none yet | Same checks. |
| 4 | `Management` | `security` | Same checks. Last, because `security` holds Identity Center and the audit log bucket. |

Rollback, fastest first. One command per policy per OU (policy IDs from the sensitive output `scp_policy_ids`, the OU ID from `aws organizations list-organizational-units-for-parent`):

```sh
aws organizations detach-policy --policy-id <policy id> --target-id <OU id> --profile <management profile>
```

Then revert the stage in a PR (restore the previous default of `scp_attachments`) so that Terraform agrees: until then the next plan wants to re-attach it.

## Limits to know

- AWS allows **five SCPs directly attached to an OU**. `FullAWSAccess` plus the four baseline SCPs is exactly five, so after a stage no further SCP can be attached to that OU without removing one (the same at every stage). The hand-made root SCP already denies `LeaveOrganization`, so `deny-leave-organization` is partly redundant with it: merging policies or dropping one is a later decision, not part of the rollout.
- The region SCP exempts only the services of `global_service_prefixes`. Console panels that call services served from `us-east-1` only (Health, Trusted Advisor, parts of the console home) will show access-denied messages in a member account. They are explicit denies that change nothing; a prefix is added only in the PR that needs it (`docs/ORGANIZATION_INPUTS.md`).

## Proofs

Output is recorded with account and organization IDs left out.

**Every simulator call must pass `--context-entries ContextKeyName=aws:RequestedRegion,ContextKeyValues=<allowed region>,ContextKeyType=string`.** Without it the region SCP fires on any action outside its exception list (`StringNotEquals` on a missing key is true), so even a control such as `s3:ListAllMyBuckets` looks denied and the result proves nothing. At stage 1 the first run without it showed exactly that, and the controls were only valid once the key was supplied.

| SCP | Proof |
|---|---|
| `deny-leave-organization` | **Never a real call**: if the SCP failed, the account would leave the Organization. `aws iam simulate-principal-policy`, run **by a role inside the member account** (called from the management account it would report an SCP-free evaluation), `OrganizationsDecisionDetail.AllowedByOrganizations` false, and `list-policies-for-target` for presence. Limit: `DenyLeaveAndCloseAccount` also denies this action, so the simulator cannot say which policy denied it. |
| `deny-root-user` | The simulator needs a user or role as its source, so the root cannot be simulated directly: the proof passes `aws:PrincipalArn` set to the account's root ARN with `--context-entries`, and compares with a normal SSO role (allowed). The simulator honours the override (checked at stage 1: the root ARN is denied, a normal role is allowed). No real root session is ever created, so the end-to-end effect on a real root user is not exercised. |
| `deny-disable-cloudtrail` | A harmless real call, `aws cloudtrail stop-logging --name no-such-trail-$(uuidgen)` in the allowed region, from an admin role in the account. The name must be random, **never a real trail name and never an ARN**: if the SCP were not yet effective, a real name would stop that trail. With the SCP the error says explicit deny in a service control policy; without it, `TrailNotFoundException`. A caller with no cloudtrail permission gets an implicit-deny message instead, which is not the proof. |
| `deny-outside-allowed-region` | A harmless real call, `ec2 describe-regions` in another region, is denied; the same call in the allowed region, `iam get-account-summary` and `sts get-caller-identity` succeed. |

For an OU with no account (`Environments`, `Operations`) there is no principal to call from: the proof is that the policies are attached, and the effect is unproven until the first account arrives, which is then checked at its creation.

After each stage: the CI role of the account still assumes through OIDC (STS is an exception of the region SCP) and a plan in that account is a no-op; after the `Management` stage, Identity Center and the audit log bucket are still reachable.

Bedrock cross-region inference in `workforce` is an open risk of the region SCP (`docs/ORGANIZATION_INPUTS.md`). It is tried after stage 1 with the `eu.` and `global.` inference profiles if model access exists, and otherwise left to the model provider story. If it fails, the rollback is to detach the region SCP from `Development`, never to widen the Deny during the rollout.

## Evidence

Filled in as the stages are applied.

| Stage | OU | Applied | Proofs |
|---|---|---|---|
| 0 | none | 2026-10-03, by CI after the approval of the `management` environment | The four baseline policies exist with **no target** (`list-targets-for-policy`); `DenyLeaveAndCloseAccount` imported unchanged (content identical, now tagged) and still attached to the root with `FullAWSAccess`; no SCP attached to any OU (each OU has only `FullAWSAccess`); the run's drift checks of `bootstrap`, `security` and `workforce` passed. |
| 1 | Development | 2026-10-03, by CI after the approval of the `management` environment: plan `4 to add, 0 to change, 0 to destroy`, `Apply complete! 4 added`; every job of the run green | See the list below. |
| 2 | Environments | this stage's PR; apply pending | pending |
| 3 | Operations | pending | pending |
| 4 | Management | pending | pending |

### Stage 1 (Development, account `workforce`), proofs of 2026-10-03

- **Attachment.** Development has `FullAWSAccess` and the four baseline SCPs attached directly (five, the limit). Each baseline policy has exactly one target, Development. Management, Environments and Operations have only `FullAWSAccess`. The root has `DenyLeaveAndCloseAccount` and `FullAWSAccess`.
- **Controls, from a `WorkforceAdministrator` session inside the account.** `sts get-caller-identity` works in `eu-south-1` and through the global endpoint (`us-east-1`); `iam get-account-summary` works; `ec2 describe-regions` in `eu-south-1` works.
- **`deny-outside-allowed-region`.** `ec2 describe-regions --region us-west-2` fails with an explicit deny in a service control policy, and the policy named in the error is `deny-outside-allowed-region`.
- **`deny-disable-cloudtrail`.** `cloudtrail stop-logging` with a random nonexistent name fails with an explicit deny in a service control policy naming `deny-disable-cloudtrail`. Control, management account (SCPs never apply), same call with another random name: `TrailNotFoundException`. The real organization trail kept logging with no delivery error.
- **`deny-leave-organization`.** Never a real call. The simulator, run from the role inside the account with the region key supplied: `explicitDeny`, `AllowedByOrganizations` false. The controls `s3:ListAllMyBuckets` and `iam:GetAccountSummary` are allowed. Not attributable to this policy alone: the root SCP `DenyLeaveAndCloseAccount` also denies the action.
- **`deny-root-user`.** The simulator with `aws:PrincipalArn` set to the account's root ARN: `explicitDeny`; a normal role: allowed. No real root session exists, so the effect on a real root user is not exercised.
- **Before the stage.** The account had no tagged resource in `eu-south-1`; the only one reported in `us-east-1` was the global GitHub OIDC provider.
- **Not yet proved.** The CI role of the account under the SCPs: the `workforce` drift check of the apply run ran with the SCPs not yet attached, so the first run after the attachment (the next merge that touches Terraform paths) is the proof. Bedrock cross-region inference was not tried (no model access in the account yet; left to the model provider story).
