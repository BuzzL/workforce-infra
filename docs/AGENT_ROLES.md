# Agent roles

The developer agent reads the `test`, `quality` and `demo` accounts through one role each, `<key>-foundation-agent-role` (`test`, `qual`, `demo`), under `/platform/`. The permission set and the trust are the decision of `docs/ENVIRONMENT_PERMISSIONS.md` ("Agent role"); this document says how they are built and applied.

## What exists

- `modules/agent-role`: the read only permission set of the decision, for the registered applications (`testbed`), on top of `modules/cross-account-role`. The set is identical in every environment, so `demo` ⊆ `quality` ⊆ `test` holds with equality. Its tests assert the set literally, the trust literally, the inclusions and that nothing writes, escalates or downloads code or templates.
- `agent.tf` in `bootstrap/accounts/test`, `quality` and `demo`: instantiates the module, off until the variable `agent` is set.

## Why a local apply

The role is an IAM resource, and the CI apply role of an account has no IAM write permission (`docs/ACCOUNT_CI_BASELINES.md`, decision 2): CI could otherwise widen its own access. So the agent roles are part of the baseline stack of each account, applied locally with the maintainer's session, like the CI roles. CI plans the stack through the plan role, which gains read of this one role (`extra_read_statements`) so that the drift check stays a no-op. Nothing in `live/environments/<name>` changes.

## Applying

The trusted principal is the agent task role of `workforce`, `wrkf-foundation-agent-role` under `/platform/`, defined in `bootstrap/accounts/workforce/agent_role.tf`. ECS tasks of that account assume it and it starts with no permissions: each one arrives with the change that needs it (the ECS stack IAT-60, and the permission to assume the three agent roles). Applied locally, like every IAM resource of a baseline.

1. Apply `bootstrap/accounts/workforce` (the maintainer's session in the account). Merging before this apply makes the post-merge drift job fail until it is applied, so apply from the pull request branch first.
2. `scripts/set-agent-role-vars.sh` creates one ExternalId per environment (64 random hex characters) and writes `agent` into the gitignored `terraform.tfvars` of `bootstrap/accounts/test`, `quality` and `demo`, between marker lines, with the principal read from step 1. Existing values are never overwritten; the file is mode 600; nothing is printed except names and counts. `--check` lists the counts.
3. In each of the three stacks: `terraform plan`, review (one role, one inline policy, and the read of that one role added to the plan role), then `terraform apply`.
4. Store each ExternalId in Secrets Manager in `workforce`, readable by the agent task role only (the secret containers are IAT-54).
5. Check with a real call from the task: `sts:AssumeRole` with session name `agent-<task id>` and the ExternalId succeeds, any other session name or a missing ExternalId is denied. Prove first whether `aws:PrincipalArn` carries the IAM path of the task role (open item of `docs/ENVIRONMENT_PERMISSIONS.md`): if the assume is denied with the path-bearing ARN, the task role needs no path or the condition value must change.

The ExternalId and the principal ARN sit in the `terraform.tfvars` files, which supersedes the GitHub Environment secret mentioned in `docs/ENVIRONMENT_PERMISSIONS.md` (these stacks are applied locally, so CI never reads them). They reach the baseline state, which the decision accepts for the ExternalId.

Rotation: `scripts/set-agent-role-vars.sh --rotate` (new value in front, current kept) and apply; switch the secret in `workforce`; `--drop-old` and apply.

## Before CI plans these stacks

`.ci-enabled` must not be added to `bootstrap/accounts/test`, `quality` or `demo` until the value of `agent` reaches CI as a secret (`TF_VAR_agent`, like `audit_log_bucket_name`, with `scripts/redact.sh` checked so that the ExternalId never appears in a plan comment). CI plans without it see `agent = null` and propose to destroy the role, which fails the drift check on every run. This belongs to the change that enables these stacks in CI (IAT-79).
