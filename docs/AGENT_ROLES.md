# Agent roles

The developer agent reads the `test`, `quality` and `demo` accounts through one role each, `<key>-foundation-agent-role` (`test`, `qual`, `demo`), under `/platform/`. The permission set and the trust are the decision of `docs/ENVIRONMENT_PERMISSIONS.md` ("Agent role"); this document says how they are built and applied.

## What exists

- `modules/agent-role`: the read only permission set of the decision, for the registered applications (`testbed`), on top of `modules/cross-account-role`. The set is identical in every environment, so `demo` ⊆ `quality` ⊆ `test` holds with equality. Its tests assert the set literally, the trust literally, the inclusions and that nothing writes, escalates or downloads code or templates.
- `agent.tf` in `bootstrap/accounts/test`, `quality` and `demo`: instantiates the module, off until the variable `agent` is set.

## Why a local apply

The role is an IAM resource, and the CI apply role of an account has no IAM write permission (`docs/ACCOUNT_CI_BASELINES.md`, decision 2): CI could otherwise widen its own access. So the agent roles are part of the baseline stack of each account, applied locally with the maintainer's session, like the CI roles. CI plans the stack through the plan role, which gains read of this one role (`extra_read_statements`) so that the drift check stays a no-op. Nothing in `live/environments/<name>` changes.

## Applying

The trusted principal is the agent task role in `workforce`, which does not exist until the ECS stack (IAT-60). IAM refuses a trust policy that names a role that is not there, so the variable stays unset until then.

1. Generate one ExternalId per environment and store it in Secrets Manager in `workforce` (readable by the agent task role only), see `docs/ENVIRONMENT_PERMISSIONS.md`.
2. Set `agent` in the gitignored `terraform.tfvars` of `bootstrap/accounts/<name>` (shape in `terraform.tfvars.example`): principal ARN, workforce account ID, ExternalId.
3. `terraform plan`, review (one role, one inline policy, and the read of that one role added to the plan role), then `terraform apply`.
4. Check with a real call from the task: `sts:AssumeRole` with session name `agent-<task id>` and the ExternalId succeeds, any other session name or a missing ExternalId is denied.

4b. The ExternalId and the principal ARN sit in the gitignored `terraform.tfvars` of the baseline stack, which supersedes the GitHub Environment secret mentioned in `docs/ENVIRONMENT_PERMISSIONS.md` (that stack is applied locally, so CI never reads it). They reach the baseline state, which the decision accepts for the ExternalId. Prove first whether `aws:PrincipalArn` carries the IAM path of the task role (open item of that document): if the assume is denied with the real path-bearing ARN, the task role needs no path or the condition value must change.

Rotation: set both ExternalIds, apply, switch the secret in `workforce`, remove the old value, apply.

## Before CI plans these stacks

`.ci-enabled` must not be added to `bootstrap/accounts/test`, `quality` or `demo` until the value of `agent` reaches CI as a secret (`TF_VAR_agent`, like `audit_log_bucket_name`, with `scripts/redact.sh` checked so that the ExternalId never appears in a plan comment). CI plans without it see `agent = null` and propose to destroy the role, which fails the drift check on every run. This belongs to the change that enables these stacks in CI (IAT-79).
