# Deploy roles

The testbed's pipeline deploys into the `test`, `quality` and `demo` accounts through one role each, `<key>-foundation-testbed-deploy-role` (`test`, `qual`, `demo`), under `/platform/`. The permission set and the trust are the decision of `docs/ENVIRONMENT_PERMISSIONS.md` ("Deploy role"); this document says how they are built and applied.

## What exists

- `modules/deploy-role`: the deploy table of the decision for one application, on top of `modules/cross-account-role`. The trust is web identity: the account's GitHub OIDC provider, `StringEquals` on `aud` and on one exact `sub`, the application's repository (owner and repository IDs) in the GitHub Environment of the account (`test`, `quality`, `demo`: the environment **name**, never the key). Its tests assert both sets and the trust literally, the inclusions `demo` ⊆ `quality` ⊆ `test`, the overlap with the agent role, and that nothing creates a role, chains, updates a stack or writes a Lambda directly.
- `deploy.tf` in `bootstrap/accounts/test`, `quality` and `demo`: instantiates the module, off until the variable `deploy` is set. `modules/account-ci-baseline` exposes the provider it trusts as `oidc_provider_arn`.

The set differs between environments in two ways. `test` may create and delete stacks and names any stack of the application. `quality` and `demo` allow only the registered stacks and neither action. `quality` and `demo` are equal: what narrows `demo` is the reviewer on its GitHub Environment and its execution role (`docs/ENVIRONMENT_PERMISSIONS.md`, "Narrowing rule").

## Inputs

`deploy` is one object in the gitignored `terraform.tfvars` (`terraform.tfvars.example` shows it): the numeric GitHub ID of the repository, the artifact bucket and the artifact prefix, and optionally the repository name and the registered stack qualifiers (defaults `workforce-testbed` and `main`). The owner is the one of the baseline. All of it is public, none is a secret. The artifact location is a placeholder until the first deployable creates it (`docs/ENVIRONMENT_PERMISSIONS.md`, open items).

## Why a local apply

Like the agent roles (`docs/AGENT_ROLES.md`): the role is an IAM resource and the CI apply role has no IAM write permission (`docs/ACCOUNT_CI_BASELINES.md`, decision 2). The roles are part of the baseline stack of each account, applied locally with the maintainer's session. CI plans the stack through the plan role, which reads this one role (`extra_read_statements`).

## Preconditions

- The execution role `<key>-foundation-testbed-exec-role` does not exist yet. `iam:PassRole` names it, so the deploy role can be created first but cannot deploy until it exists.
- The GitHub Environments restrict the refs (`feature/*` and `bugfix/*` for `test`, `main` for `quality`, `v*` tags for `demo`): the `sub` carries no ref (`docs/ENVIRONMENTS.md`).
- The template is loaded from the artifact in the **virtual-hosted URL form** `https://<bucket>.s3.<region>.amazonaws.com/<prefix>/...`. The `cloudformation:TemplateUrl` condition does not match the path-style form (`https://s3.<region>.amazonaws.com/<bucket>/...`), so the pipeline must pass the former.
- The pipeline passes the stack tags (`App`, `Environment` and the others of `docs/TAG_CONVENTION.md`) on every create and update, because no condition key tells the two apart. Tag keys are restricted only on `TagResource` and `UntagResource` (`aws:TagKeys`), not at creation, and tag values are not restricted there: tags describe, names authorize (`docs/TAG_CONVENTION.md`).

## CI and the `deploy` variable

CI plans `bootstrap/accounts/test`, `quality` and `demo` with `deploy = null`, as it does for `agent`. A role applied locally would show in every CI plan as a change to destroy, which fails the drift check. None of the three has the variable set at present, so the plans are no-ops. Setting it for real needs CI to receive the same `deploy` value (it holds no secret, so a GitHub Environment variable passed as `TF_VAR_deploy` is enough), in its own change.
