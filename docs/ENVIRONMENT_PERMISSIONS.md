# Environment permission model

## Context

Workforce reaches the `test`, `quality` and `demo` accounts through narrowly scoped cross-account roles. This document is the decision, taken before any code: which roles exist, who may assume them, what each may do and may not do, and how the permissions narrow along the promotion path (`docs/ENVIRONMENTS.md`). Later issues implement it and do not change it: a new need is a new decision record here.

Scope of the decision:

- **The environment accounts hold applications, not infrastructure that Terraform owns.** A deployable repository (the testbed first) creates and updates its own resources through CloudFormation (SAM or CDK, chosen in M7), in its own pipeline. `workforce-infra` provides only the *access*: the roles below. It never owns an application's function, queue or service.
- **The first workload is serverless, Lambda with an alias,** because it costs nothing to maintain. The model is a catalogue of **archetypes** so that another repository with the same kind of workload is enabled by instantiating a template, not by writing a policy. Further archetypes (`ecs-service`, `ecs-task`) are future sections of this document.
- Placeholders only. No account IDs, emails or ARNs are written here (`scripts/check-docs-public.sh` enforces it).

## Naming rule

Every resource these roles create or may touch is named

> `<env>-<project>-<name>-<resource>`

in this order, with hyphens between the parts:

| Part | Content | Rule |
|---|---|---|
| `<env>` | the four-letter **key** of the environment (`test`, `qual`, `demo`, from `scripts/environment-keys.tsv`) | always the first four characters |
| `<project>` | `workforce` | fixed for everything this repository owns |
| `<name>` | what the resource belongs to or does: `agent`, `platform`, or a registered application (`testbed`), optionally followed by a qualifier (`testbed-deploy`, `testbed-main`) | lowercase letters and digits, hyphens between segments |
| `<resource>` | the type of the resource, last | one word from a closed list: `role`, `policy`, `boundary`, `stack`, `function`, `alias`, `alarm` |

A name therefore reads from the broadest to the most specific part and can be checked with one strict regexp anchored on four characters, `^(test|qual|demo)-workforce-[a-z0-9]+(-[a-z0-9]+)*-(role|policy|boundary|stack|function|alias|alarm)$`. A key is never accepted where a name is expected (`docs/ENVIRONMENTS.md`).

An application's `<name>` starts with its **application name**, one segment registered below. `agent` and `platform` are reserved, so no application name can match a platform name.

| Application | Repository | Archetype |
|---|---|---|
| `testbed` | `workforce-testbed` | `lambda` |

Adding an application is one row here plus one instantiation per environment. IAT-46 asserts that every name in a policy matches the regexp and that its application is registered.

| Resource | Name | Path |
|---|---|---|
| Agent role (one per environment, shared) | `<env>-workforce-agent-role` | `/platform/` |
| Permissions boundary (one per environment, shared) | `<env>-workforce-platform-boundary` | `/platform/` |
| Deploy role (one per application) | `<env>-workforce-<app>-deploy-role` | `/platform/` |
| CloudFormation execution role (one per application) | `<env>-workforce-<app>-exec-role` | `/platform/` |
| Stack of an application | `<env>-workforce-<app>-<qualifier>-stack` | |
| Function, alias, alarm of an application | `<env>-workforce-<app>-<qualifier>-function`, `-alias`, `-alarm` | |
| IAM role an application creates | `<env>-workforce-<app>-<qualifier>-role` | `/apps/` |

`<qualifier>` is one or more segments that tell resources of the same type apart (`main`, `api`). The log group of a function is named by Lambda after the function: `/aws/lambda/<function name>`.

**Platform and application roles are told apart by the IAM path,** not by the name: the execution role may create and pass roles under `/apps/<env>-workforce-<app>-*-role` only, so it can never match `/platform/` roles (the deploy role, itself, the agent role, the boundary), whatever an application names its resources. A key is never accepted where a name is expected (`docs/ENVIRONMENTS.md`).

Each application has **its own deploy and execution roles**: the deploy role of one application can pass only its own execution role, whose policy covers only its own `<env>-workforce-<app>-*` resources, so one repository cannot reach another's.

## Roles and trust

| Role | Used by | Trust |
|---|---|---|
| `<env>-workforce-agent-role` | the developer agent (ECS task in `workforce`) | `sts:AssumeRole` |
| `<env>-workforce-<app>-deploy-role` | the deploy job of the application repository | `sts:AssumeRoleWithWebIdentity` (GitHub OIDC) |

### Agent role: `sts:AssumeRole` from `workforce`

The trust policy names one principal, the agent task role in the `workforce` account, by exact ARN (`aws:PrincipalArn`), and requires all of:

- the source account, through the principal (no `*` principal, no account root);
- `sts:ExternalId`, equal to the environment's ExternalId;
- `sts:RoleSessionName` `StringLike` `agent-*`, so that CloudTrail attributes a session to an agent task. The task names its session `agent-<task id>`.

**Where the ExternalId lives.** In Secrets Manager in the `workforce` account, one secret per environment, readable by the agent task role only. It is never a GitHub secret: the agent does not run in GitHub Actions. The environment account stack receives the value as a sensitive Terraform variable, from a secret of its GitHub Environment. Sensitive values still reach the Terraform state, which is acceptable because the ExternalId is not a credential: it prevents the confused-deputy case, the access control is the principal ARN. It is never in the repo or in logs (`scripts/redact.sh`).

**Rotation.** Create the new value, apply the role with both values accepted, switch the secret in `workforce`, apply again with the old value removed. Every step is a reviewed change.

### Deploy role: GitHub OIDC, one subject per GitHub Environment

The trust policy is the pattern of `modules/account-ci-baseline`: the account's GitHub OIDC provider, `StringEquals` (never `StringLike`) on `aud` and on `sub`, where `sub` is the exact subject of one repository in one GitHub Environment (`repo:<owner>@<owner id>/<repository>@<repository id>:environment:<name>`). The `demo` environment has a required reviewer, so AWS only issues credentials after the maintainer approved the deployment. This is the reason for choosing OIDC over chaining through a `workforce` role: the gate is visible in the trust, not only in GitHub.

**The `sub` carries the environment but no ref.** The branch restriction is therefore a **precondition** held by the GitHub Environment, not by AWS: `test` accepts `feature/*` and `bugfix/*`, `quality` only `main`, `demo` only `v*` tags (`docs/ENVIRONMENTS.md`, in `workforce-github`). Without it, any workflow naming the environment could assume the role. IAT-79 verifies it.

**There is no ExternalId on this role.** `sts:ExternalId` exists only for `AssumeRole`, not for web identity. Its control here is the exact `sub`, which carries the repository and environment IDs, and the environment's own protection. Consequence for the module (IAT-43): it supports two trust modes, `AssumeRole` with the three required conditions and `WebIdentity` with the exact subject, and refuses anything else.

## Archetypes

An **archetype** is a named permission template: the actions allowed with the resource-name patterns they apply to, the narrowing per environment, and the reason for each. Enabling a repository to deploy a kind of workload into an environment is one instantiation of the role module with that archetype and that repository's subject. An archetype is only ever added, never edited: a change in its permissions is a new decision.

- The **deploy role** may do only what is needed to start a CloudFormation deployment: act on stacks named `<env>-workforce-<app>-*-stack`, read the artifact, and pass **one** role, its own `<env>-workforce-<app>-exec-role`, to CloudFormation.
- The **execution role** creates the resources. Its policy is the archetype's real permission set. The OIDC identity therefore never holds create rights over application resources.
- The **permissions boundary** `<env>-workforce-platform-boundary` caps every role a stack creates for the application, so the application cannot grant itself more than the archetype allows.
- The **agent role** only reads.

All platform roles and the boundary are created by the environment account's stack in `workforce-infra`, applied through the gated CI (order of changes: the CI-permissions-first rule in `CLAUDE.md`). The application's resources are created by its pipeline.

**Bootstrap and recovery are the maintainer's, not a role's.** The first creation of an application's stack in `quality` and `demo`, and the recovery of a stack stuck in `CREATE_FAILED` or `ROLLBACK_COMPLETE` (which can only be deleted), are done by the maintainer from the SSO admin session, like the account baselines (`docs/ACCOUNT_CI_BASELINES.md`), and noted in the Linear issue. No role in `quality` or `demo` can create or delete a stack. `test` can, because its stacks are ephemeral.

## Archetype `lambda`

The reason column is part of the decision: a statement without one is not allowed. Rows headed "Not allowed" are the **absence of an Allow** or an Allow narrowed by a condition. None of them is a `Deny` statement, so none can lock a principal out. They are asserted as calls that must fail (IAT-46).

**Resource `*` exception.** A few actions do not support resource-level permissions and need `Resource: "*"`: `cloudwatch:DescribeAlarms`, `logs:DescribeLogGroups` and `cloudformation:GetTemplateSummary`. They are read-only actions on names and metadata, listed in the tables as "(resource `*`)". Nothing else has a `*` resource. This is the only exception to the `*` rule in `CLAUDE.md` and it needs the maintainer's approval in this review.

**No secrets in function configuration.** Environment variables of a function carry names and endpoints, never secrets (a secret is referenced by its Secrets Manager name and read at runtime). This is what lets the agent read configuration.

### `<env>-workforce-agent-role` (identical in all environments)

| Allowed | Resource | Reason |
|---|---|---|
| `lambda:GetFunctionConfiguration`, `lambda:GetAlias`, `lambda:ListVersionsByFunction`, `lambda:ListAliases` | functions `<env>-workforce-<app>-*-function` | the agent checks what is deployed. `GetFunction` is left out: it returns a pre-signed URL to the code package |
| `cloudformation:DescribeStacks`, `DescribeStackEvents` | stacks `<env>-workforce-<app>-*-stack` | the agent reads a failed deployment. `GetTemplate` is left out: templates may name internal resources |
| `logs:GetLogEvents`, `logs:FilterLogEvents`, `logs:DescribeLogStreams` | log groups `/aws/lambda/<env>-workforce-<app>-*-function` | the agent reads the logs of the code it changed |
| `cloudwatch:DescribeAlarms` (resource `*`) | | the agent reads the canary and health state |

Opening a release is a GitHub operation and needs nothing in AWS, so the agent role has no write action of any kind.

| Not allowed | Reason |
|---|---|
| any `lambda`, `cloudformation`, `logs`, `cloudwatch` write action | the agent proposes changes through pull requests, it does not deploy |
| `iam:*`, `sts:AssumeRole` | no privilege escalation, no role chaining |
| `secretsmanager:*`, `kms:*`, `s3:*`, `lambda:GetFunction` | the agent needs no secret, no data and no code download |

### `<env>-workforce-<app>-deploy-role`

| Capability | Resource | `test` | `quality` | `demo` | Reason |
|---|---|---|---|---|---|
| `cloudformation:CreateStack`, `DeleteStack` | stacks `<env>-workforce-<app>-*-stack` | yes | no | no | `test` deploys every pull request, so it creates and deletes ephemeral stacks |
| `cloudformation:CreateChangeSet` with `cloudformation:ChangeSetType` `UPDATE` | same | yes | yes | yes | the update path. A `CREATE` change set would create a stack, so it is allowed in `test` only |
| `cloudformation:CreateChangeSet` with `ChangeSetType` `CREATE` | same | yes | no | no | as above |
| `cloudformation:ExecuteChangeSet`, `DeleteChangeSet`, `UpdateStack`, `DescribeStacks`, `DescribeStackEvents`, `DescribeChangeSet`, `GetTemplate` | same | yes | yes | yes | follow and finish a deployment of this application only |
| `cloudformation:GetTemplateSummary` (resource `*`) | | yes | yes | yes | reads the template before a change set |
| `iam:PassRole` of `<env>-workforce-<app>-exec-role`, condition `iam:PassedToService` = `cloudformation.amazonaws.com` | that one role | yes | yes | yes | CloudFormation needs the execution role, and only that one |
| `s3:GetObject` | the artifact prefix of the repository | yes | yes | yes | the deployment reads the artifact built once in CI (`docs/ENVIRONMENTS.md`) |
| `lambda:GetFunctionConfiguration`, `lambda:GetAlias` | functions `<env>-workforce-<app>-*-function` | yes | yes | yes | the post-deploy health check |
| `cloudwatch:DescribeAlarms` (resource `*`) | | yes | yes | yes | the canary reads the alarm that triggers a rollback |

| Not allowed | Reason |
|---|---|
| a stack not named `<env>-workforce-<app>-*-stack` | a repository cannot touch another application or the environment's own resources |
| any `iam` action other than the one `PassRole` above | the deploy identity cannot create or change a role, a policy or a user |
| `iam:PassRole` of any other role, including another application's | no way around the execution role |
| `lambda:*` write actions, directly | resources change only through the stack, so every change is in a template and a change set |
| `organizations:*`, `account:*`, `sts:AssumeRole` | no organization access, no chaining |

### `<env>-workforce-<app>-exec-role` (the real permission set)

Resources are the application's, `<env>-workforce-<app>-*-<resource>`. Roles are `role/apps/<env>-workforce-<app>-*-role`.

| Capability | `test` | `quality` | `demo` | Reason |
|---|---|---|---|---|
| `lambda:UpdateFunctionCode`, `UpdateFunctionConfiguration`, `PublishVersion`, `UpdateAlias`, `GetFunction`, `GetFunctionConfiguration`, `GetAlias`, `TagResource`, `UntagResource` | yes | yes | yes | releasing a version and moving the alias, which is what a canary shifts weights on |
| `lambda:CreateFunction`, `CreateAlias`, `AddPermission` | yes | yes | no | a resource new to the template is created in `quality` first. `demo` does not create resources: a missing one means a maintainer bootstrap |
| `lambda:DeleteFunction`, `DeleteAlias`, `RemovePermission` | yes | no | no | `quality` and `demo` never destroy |
| `logs:CreateLogGroup`, `PutRetentionPolicy`, `TagResource` | yes | yes | no | retention is set by the stack, so logs do not grow without bound |
| `logs:DeleteLogGroup` | yes | no | no | never destroy |
| `cloudwatch:PutMetricAlarm` | yes | yes | no | the health and rollback alarms (`demo` changes none) |
| `cloudwatch:DeleteAlarms` | yes | no | no | never destroy |
| `iam:CreateRole`, `AttachRolePolicy`, `PutRolePolicy`, `TagRole` | yes | yes | no | the function's execution role, with the boundary |
| `iam:DeleteRole`, `DetachRolePolicy`, `DeleteRolePolicy` | yes | no | no | never destroy |
| `iam:GetRole`, `iam:PassRole` (condition `iam:PassedToService` = `lambda.amazonaws.com`) | yes | yes | yes | read the role, hand it to the function |
| `s3:GetObject` on the artifact prefix | yes | yes | yes | `UpdateFunctionCode` reads the package |
| `logs:DescribeLogGroups` (resource `*`) | yes | yes | yes | CloudFormation checks for an existing log group |

Conditions on the `iam` rows, all of them (not only create and attach): the role must be under `role/apps/<env>-workforce-<app>-*-role`, and for `CreateRole`, `AttachRolePolicy`, `PutRolePolicy` the role must have the boundary, compared by its **full ARN** (`iam:PermissionsBoundary`), so an existing unbounded role under the pattern cannot be edited. The trust policy of an application role names only `lambda.amazonaws.com` (`iam:UpdateAssumeRolePolicy` is not allowed, so the trust is set at creation and a change to it is a new decision).

| Not allowed | Reason |
|---|---|
| `iam:PutRolePermissionsBoundary`, `DeleteRolePermissionsBoundary`, `UpdateAssumeRolePolicy` | the application cannot remove or swap its cap, or open its trust |
| a role without the boundary, any role outside `role/apps/<env>-workforce-<app>-*-role` | no way to create an unbounded role. The `/platform/` roles, the boundary and the execution role itself are out of reach because of the path (and the name: an application's `<qualifier>` cannot end in `deploy` or `exec`, `agent` and `platform` are reserved) |
| any `iam` action on users or groups | not part of the archetype |
| any resource outside the patterns above | there is no `*` resource in an Allow except the exception above |
| VPC, EC2, data stores, CodeDeploy | not part of the `lambda` archetype. A workload that needs them, or canary through CodeDeploy, is a new archetype. This one shifts weight on the alias through `UpdateAlias` |

### `<env>-workforce-platform-boundary`

The permissions boundary lists the actions an application role may ever have: writing its own logs (`logs:CreateLogStream`, `logs:PutLogEvents` on `/aws/lambda/<env>-workforce-<app>-*-function`) and what the workload needs at runtime, none at first. A role that needs more means a new decision here.

## Narrowing rule: `demo` ⊂ `quality` ⊂ `test`

Narrowing is **set inclusion**, tested mechanically. For a role, take the set of (action, resource pattern) pairs it allows. Then:

> allowed(`demo`) ⊆ allowed(`quality`) ⊆ allowed(`test`)

so any call allowed in `demo` is allowed in `quality` and in `test`, and the reverse is not true. Each step removes capabilities and never swaps them. The agent role is identical in the three environments (read only) and satisfies the rule with equality. For the deploy and execution roles the columns above are the decision, and the steps are proper:

- `test` → `quality`: no stack creation or deletion, and no deletion of any resource. Stack and resource creation is possible only through update, from a change set of type `UPDATE`.
- `quality` → `demo`: no creation of any resource, as well. `demo` only updates what already exists, so a release cannot grow or shrink the demo account's footprint without the maintainer.

The consequence is deliberate: an artifact that adds a resource runs in `quality` first, and `demo` needs a maintainer bootstrap step for that resource before the release. Removing a resource leaves it in place until the maintainer cleans it up.

The matrix is a table on purpose: IAT-44 and IAT-45 assert the inclusion with `terraform test`, and IAT-46 derives from each cell a call that must succeed or fail.

## Guardrails

- The M2 SCPs apply to the Environments OU. Nothing here loosens them and no SCP is added.
- No `*` principal, no `*` or `service:*` action, no `NotAction`, `NotPrincipal` or `NotResource` in an Allow, as in `CLAUDE.md`.
- The permissions boundary `<env>-workforce-platform-boundary` can lock a role out. It, the `Resource: "*"` exception above, and any `Deny` added by the implementation, need the maintainer's explicit approval in review. This decision introduces no `Deny` statement. A `Deny` may use a wildcard only when it is narrowed by a `Condition` or by specific resources, and it is asserted literally in a test.

## How later issues use this

| Issue | Takes from this document |
|---|---|
| IAT-43 cross-account role module | the two trust modes, the invariants (no `*` principal, no `*` action, no `NotAction`, ExternalId required on `AssumeRole`), the naming regexps and the IAM paths |
| IAT-44 agent role per environment | the agent table, the principal and the ExternalId scheme |
| IAT-45 deploy role per environment | the deploy and execution tables (per application), `<env>-workforce-platform-boundary`, the narrowing steps |
| IAT-46 allowed/denied matrix | every Allowed cell as a call that succeeds, every denied row as a call that fails, and every name checked against the regexps |
| IAT-42, IAT-79 CI baselines and GitHub Environments | the OIDC subjects of the deploy roles and the branch and tag restrictions of the GitHub Environments |

## Open items

- The deploy tool (SAM or CDK) is decided in M7. This model assumes CloudFormation only, and the tool must work with a pre-created execution role and boundary.
- The artifact location (the bucket and prefix named above) is created with the first deployable and written down then, as a placeholder in this document until it exists.
