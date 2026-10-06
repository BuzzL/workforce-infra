# Agent roles

The developer agent reads the `test`, `quality` and `demo` accounts through one role each, `<key>-foundation-agent-role` (`test`, `qual`, `demo`), under `/platform/`. The permission set and the trust are the decision of `docs/ENVIRONMENT_PERMISSIONS.md` ("Agent role"); this document says how they are built and applied.

## What exists

- `modules/agent-role`: the read only permission set of the decision, for the registered applications (`testbed`), on top of `modules/cross-account-role`. The set is identical in every environment, so `demo` ⊆ `quality` ⊆ `test` holds with equality. Its tests assert the set literally, the trust literally, the inclusions and that nothing writes, escalates or downloads code or templates.
- `matrix_roles.tf` in `bootstrap/accounts/workforce`: the matrix runner roles, off until the variable `matrix` is set (see "Matrix runner roles").
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

- The value is the environment secret `AGENT` of `<name>-plan`: the block of the local `terraform.tfvars` as one line, which Terraform reads from `TF_VAR_agent` as an HCL object. It holds the ExternalId of that environment only. `scripts/set-agent-role-vars.sh --set-secrets` writes it, through `gh` on stdin, from the files, after checking all three files, so that a bad file leaves the secrets as they are.
- Only the Plan step of the `plan` job gets it (`TF_VAR_agent: ${{ secrets.AGENT || 'null' }}`), and `scripts/check-workflow.sh` rejects any other use of the secret. The `apply` job never plans a baseline, so the `<name>` environments do not hold it either. Stacks that do not declare `agent` ignore it, and an environment without the secret plans with `null`.
- The ExternalId is a confused-deputy guard, not a credential: the trust also names the exact task role in `workforce` and the session name. The `-plan` environments accept any branch, so code of a pull request of this repository could print the value: masking prevents accidents only, as for the other secrets (`docs/BOOTSTRAP.md`, section 7). `scripts/redact.sh` replaces any run of 64 hex characters with `<external-id>` before output reaches a log, artifact or comment, and Terraform shows `agent` as sensitive.
- A stack whose local `agent` differs from the secret fails the drift check: run `--set-secrets` after each change of `agent`.

## Matrix runner roles

The permission matrix job of this repository (`.github/workflows/permission-matrix.yml`, `scripts/run-permission-matrix.sh`) proves the agent role of each environment with real calls. It cannot use the agent task role, which only ECS tasks assume, so each environment has a runner role in `workforce`: `wrkf-foundation-matrix-<environment>-role` under `/platform/`.

- **Trust:** GitHub OIDC, `StringEquals` on the audience and on one exact subject, this repository in the `<environment>-matrix` GitHub Environment. The subject prefix comes from `modules/account-ci-baseline` (`github_subject_prefix`).
- **Permission:** `sts:AssumeRole` on the agent role of its own environment, nothing else.
- **In return,** the agent role of that environment trusts the runner role as a second exact principal (`extra_principal_arns` of `modules/agent-role`), with the same ExternalId and the `agent-*` session name pattern as for the task role. The chain is `GitHub OIDC → matrix runner role → agent role`, so the live proof covers the agent role's permissions and its trust conditions, not the task role's link to it, which the module tests assert literally.
- **Variables:** `matrix` (`bootstrap/accounts/workforce`) holds the account ID of each environment account, in the gitignored `terraform.tfvars` and in the secret `MATRIX` of `workforce-plan`, which only the Plan step receives (`TF_VAR_matrix`, checked by `scripts/check-workflow.sh`). Without it no runner role exists.
- **Applying:** the roles are IAM resources of a baseline, so they are applied locally: `workforce` first, then `scripts/set-agent-role-vars.sh` (it reads `matrix_role_arns` from the workforce outputs, or `MATRIX_ROLE_ARNS`, and writes `extra_principal_arns` into the `agent` block), then each environment stack, then `--set-secrets` so that the CI plan stays a no-op. The role ARN of each environment is the secret `MATRIX_RUNNER_ROLE_ARN` of its `<environment>-matrix` GitHub Environment (`workforce-github`).
- **Deploy roles:** not assumed from this repository. They belong to the application's own deployment flow, which keeps the `demo` reviewer gate in the trust (`docs/ENVIRONMENT_PERMISSIONS.md`).
