# Guardrails: attaching the baseline SCPs in stages

The four baseline service control policies (`modules/scp-baseline`) are attached to the organizational units one at a time, from `live/guardrails`, and each attachment is proved. An SCP that is wrong can lock principals out, so this stack is applied **only locally**, with the management SSO admin session and the maintainer's explicit yes before every stage. CI never applies it: `scripts/ci-stacks.sh` leaves it out of both the plan and the apply matrix until a `.ci-enabled` marker is committed, which needs the CI roles to be able to read it first.

## What it manages

| Object | Source | Attached to |
|---|---|---|
| `deny-leave-organization`, `deny-root-user`, `deny-disable-cloudtrail`, `deny-outside-allowed-region` | `modules/scp-baseline` | the OUs named in `attachments` (nothing by default) |
| `DenyLeaveAndCloseAccount` | imported from a hand-made policy, `hand_made_scp.tf` | the root, as it always was |

- `attachments` maps an OU name to the baseline SCPs attached to it. Only the OU names `Management`, `Environments`, `Development` and `Operations` and the four policy names are accepted. The root and accounts cannot be named, and an OU that does not exist fails the plan. IDs are looked up, never committed.
- `DenyLeaveAndCloseAccount` denies `organizations:LeaveOrganization` and `account:CloseAccount` for every member account. It was created by hand before the stack and is the single, fixed exception to "never attach an SCP to the root". It has `prevent_destroy`. `FullAWSAccess`, also attached to the root, is AWS-managed and never touched.
- The management account is never affected by SCPs. Its access stays the fallback if a member account is locked out: from there, assume `OrganizationAccountAccessRole` in the member account, or detach the policy.

## How to apply

From `live/guardrails`, with `backend.hcl` and `terraform.tfvars` filled from the `.example` files (both gitignored) and the management admin session (`AWS_PROFILE=<management profile>`):

```sh
terraform init -backend-config=backend.hcl
terraform plan          # shown first, always
terraform apply         # only after the maintainer's explicit yes for this stage
```

## Stages

Each stage is one attachment of the four SCPs to one OU, and its proofs. Every plan names its rollback.

| Stage | Change in `terraform.tfvars` | Accounts reached | Before the stage |
|---|---|---|---|
| 0 | `attachments = {}` | none | Creates the four policies, imports `DenyLeaveAndCloseAccount` and its root attachment (a plan of 2 to import, 4 to add, 1 to change, which is only the default tags of the imported policy, 0 to destroy). The four new policies have no target. |
| 1 | `Development` | `workforce` | `list-accounts-for-parent`, `list-policies-for-target` (`FullAWSAccess` still attached), fallback path checked. |
| 2 | `Environments` | none yet | Same checks. |
| 3 | `Operations` | none yet | Same checks. |
| 4 | `Management` | `security` | Same checks. Last, because `security` holds Identity Center and the audit log bucket. |

The plan of a stage must contain only `+ aws_organizations_policy_attachment` for that OU. Rollback, one command per policy per OU, then reconcile Terraform (remove the entry from `attachments` and apply, or `terraform state rm`):

```sh
aws organizations detach-policy --policy-id <policy id> --target-id <OU id> --profile <management profile>
```

## Proofs

Output is recorded with account and organization IDs left out.

| SCP | Proof |
|---|---|
| `deny-leave-organization` | **Never a real call**: if the SCP failed, the account would leave the Organization. `iam simulate-principal-policy` from a role inside the account, `OrganizationsDecisionDetail.AllowedByOrganizations` false, and `list-policies-for-target` for presence. Limit: `DenyLeaveAndCloseAccount` also denies this action, so the simulator cannot say which policy denied it. |
| `deny-root-user` | The simulator with `aws:PrincipalArn` set to the account's root ARN (not allowed), and a normal SSO role (still allowed). Limit: no real root session is ever created, so the end-to-end effect on a real root user is not exercised. |
| `deny-disable-cloudtrail` | A harmless real call: `aws cloudtrail stop-logging --name <a trail that does not exist>` in the allowed region. With the SCP the error says explicit deny in a service control policy; without it, `TrailNotFoundException`. The real trail is never named. |
| `deny-outside-allowed-region` | A harmless real call, `ec2 describe-regions` in another region, is denied; the same call in the allowed region, `iam get-account-summary` and `sts get-caller-identity` succeed. |

For an OU with no account (`Environments`, `Operations`) there is no principal to call from: the proof is that the policies are attached, and the effect is unproven until the first account arrives, which is then checked at its creation.

After each stage: the CI role of the account still assumes through OIDC (STS is an exception of the region SCP) and a plan in that account is a no-op; after the `Management` stage, Identity Center and the audit log bucket are still reachable.

Bedrock cross-region inference in `workforce` is an open risk of the region SCP (`docs/ORGANIZATION_INPUTS.md`). It is tried after stage 1 with the `eu.` and `global.` inference profiles if model access exists, and otherwise left to the model provider story. If it fails, the rollback is to detach the region SCP from `Development`, never to widen the Deny during the rollout.

## Evidence

Filled in as the stages are applied.

| Stage | OU | Applied | Proofs |
|---|---|---|---|
| 0 | none | pending | pending |
| 1 | Development | pending | pending |
| 2 | Environments | pending | pending |
| 3 | Operations | pending | pending |
| 4 | Management | pending | pending |
