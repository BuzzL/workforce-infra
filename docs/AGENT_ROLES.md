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
4. `scripts/set-agent-role-vars.sh --set-secrets` sets the secret `AGENT` in `test-plan`, `quality-plan` and `demo-plan` (needs `gh` as the maintainer), so that the CI plan of the baselines is a no-op (see "CI and the `agent` variable"). Do it after the apply and after every change of `agent`.
5. Store each ExternalId in Secrets Manager in `workforce`, readable by the agent task role only (the secret containers are IAT-54).
6. Check with a real call from the task: `sts:AssumeRole` with session name `agent-<task id>` and the ExternalId succeeds, any other session name or a missing ExternalId is denied. Prove first whether `aws:PrincipalArn` carries the IAM path of the task role (open item of `docs/ENVIRONMENT_PERMISSIONS.md`): if the assume is denied with the path-bearing ARN, the task role needs no path or the condition value must change.

The ExternalId and the principal ARN sit in the `terraform.tfvars` files, which supersedes the GitHub Environment secret mentioned in `docs/ENVIRONMENT_PERMISSIONS.md` (these stacks are applied locally, so CI never reads them). They reach the baseline state, which the decision accepts for the ExternalId.

Rotation: `scripts/set-agent-role-vars.sh --rotate` (new value in front, current kept) and apply, then `--set-secrets`; switch the secret in `workforce`; `--drop-old` and apply, then `--set-secrets` again.

## CI and the `agent` variable

CI plans `bootstrap/accounts/test`, `quality` and `demo` (`.ci-enabled`) through the `<name>-plan` environments, on pull requests and after a merge. The baseline is applied locally with `agent` set, so CI needs the same value: without it the plan shows the role as a destroy and the policies of both CI roles as changed, and the drift check after a merge fails the whole run (IAT-92).

- The value is the environment secret `AGENT` of `<name>-plan`: the block of the local `terraform.tfvars` as one line, which Terraform reads from `TF_VAR_agent` as an HCL object. It holds the ExternalId of that environment only. `scripts/set-agent-role-vars.sh --set-secrets` writes it, through `gh` on stdin, from the files.
- Only the `plan` job gets it (`TF_VAR_agent: ${{ secrets.AGENT || 'null' }}`). The `apply` job never plans a baseline, so the `<name>` environments do not hold the secret, and `scripts/check-workflow.sh` rejects it there. Stacks that do not declare `agent` ignore it, and an environment without the secret plans with `null`.
- The ExternalId is a confused-deputy guard, not a credential: the trust also names the exact task role in `workforce` and the session name. The `-plan` environments accept any branch, so code of a pull request of this repository could print the value: masking prevents accidents only, as for the other secrets (`docs/BOOTSTRAP.md`, section 7). `scripts/redact.sh` replaces any run of 64 hex characters with `<external-id>` before output reaches a log, artifact or comment, and Terraform shows `agent` as sensitive.
- A stack whose local `agent` differs from the secret fails the drift check: run `--set-secrets` after each change of `agent`.
