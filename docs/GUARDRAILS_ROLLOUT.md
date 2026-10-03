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

## Proofs

Output is recorded with account and organization IDs left out.

| SCP | Proof |
|---|---|
| `deny-leave-organization` | **Never a real call**: if the SCP failed, the account would leave the Organization. `aws iam simulate-principal-policy`, run **by a role inside the member account** (called from the management account it would report an SCP-free evaluation), `OrganizationsDecisionDetail.AllowedByOrganizations` false, and `list-policies-for-target` for presence. Limit: `DenyLeaveAndCloseAccount` also denies this action, so the simulator cannot say which policy denied it. |
| `deny-root-user` | The simulator needs a user or role as its source, so the root cannot be simulated directly: the proof passes `aws:PrincipalArn` set to the account's root ARN with `--context-entries`, and compares with a normal SSO role (allowed). **Verify before relying on it** that the simulator honours the override for SCP evaluation; if it does not, the proof is only the policy content and its attachment. No real root session is ever created, so the end-to-end effect on a real root user is not exercised. |
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
| 1 | Development | this stage's PR; apply pending | pending |
| 2 | Environments | pending | pending |
| 3 | Operations | pending | pending |
| 4 | Management | pending | pending |
