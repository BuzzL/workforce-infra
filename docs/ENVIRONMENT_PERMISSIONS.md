# Environment permission model

## Context

Workforce reaches the `test`, `quality` and `demo` accounts through narrowly scoped cross-account roles. This document is the decision, taken before any code: which roles exist, who may assume them, what each may do and may not do, and how the permissions narrow along the promotion path (`docs/ENVIRONMENTS.md`). Later issues implement it and do not change it: a new need is a new decision record here.

Scope of the decision:

- **The environment accounts hold applications, not infrastructure that Terraform owns.** A deployable repository (the testbed first) creates and updates its own resources through CloudFormation (SAM or CDK, chosen in M7), in its own pipeline. `workforce-infra` provides only the *access*: the roles below. It never owns an application's function, queue or service.
- **The first workload is serverless, Lambda with an alias,** because it costs nothing to maintain. The model is a catalogue of **archetypes** so that another repository with the same kind of workload is enabled by instantiating a template, not by writing a policy. Further archetypes (`ecs-service`, `ecs-task`) are future sections of this document.
- Placeholders only. No account IDs, emails or ARNs are written here (`scripts/check-docs-public.sh` enforces it).

## Naming rule

The four-letter **key** of the environment (`test`, `qual`, `demo`, from `scripts/environment-keys.tsv`) is always the **first four characters** of the name of every resource these roles create or may touch: roles, policies, stacks, log groups, the permissions boundary. A name is `<key>-<rest>`, so a policy condition or a check can use a strict regexp anchored on four characters.

| Resource | Name | Regexp |
|---|---|---|
| Agent role | `<key>-agent` | `^(test\|qual\|demo)-agent$` |
| Deploy role | `<key>-deploy` | `^(test\|qual\|demo)-deploy$` |
| CloudFormation execution role | `<key>-cfn-exec` | `^(test\|qual\|demo)-cfn-exec$` |
| Permissions boundary | `<key>-boundary` | `^(test\|qual\|demo)-boundary$` |
| Application stack, and every resource it names | `<key>-<app>-<rest>` | `^(test\|qual\|demo)-[a-z0-9]+(-[a-z0-9]+)*$` |

`<app>` is lowercase letters and digits, one segment (`testbed`), so `<key>-<app>-` is an unambiguous prefix. A key is never accepted where a name is expected (`docs/ENVIRONMENTS.md`).

## Roles and trust

Two roles per environment account, with different principals and different jobs.

| Role | Used by | Trust |
|---|---|---|
| `<key>-agent` | the developer agent (ECS task in `workforce`) | `sts:AssumeRole` |
| `<key>-deploy` | the deploy job of the application repository | `sts:AssumeRoleWithWebIdentity` (GitHub OIDC) |

### Agent role: `sts:AssumeRole` from `workforce`

The trust policy names one principal, the agent task role in the `workforce` account, by exact ARN (`aws:PrincipalArn`), and requires all of:

- the source account, through the principal (no `*` principal, no account root);
- `sts:ExternalId`, equal to the environment's ExternalId;
- a session name that starts with the task prefix, so that CloudTrail attributes a session to a task.

**Where the ExternalId lives.** In Secrets Manager in the `workforce` account, one secret per environment, readable by the agent task role only. It is never a GitHub secret: the agent does not run in GitHub Actions. The environment account stack receives the value as a sensitive Terraform variable, from a secret of its GitHub Environment, so it is not in the repo or in logs (`scripts/redact.sh`). It is not a credential: it prevents the confused-deputy case, the access control is the principal ARN.

**Rotation.** Create the new value, apply the role with both values accepted, switch the secret in `workforce`, apply again with the old value removed. Every step is a reviewed change.

### Deploy role: GitHub OIDC, one subject per GitHub Environment

The trust policy is the pattern of `modules/account-ci-baseline`: the account's GitHub OIDC provider, `StringEquals` (never `StringLike`) on `aud` and on `sub`, where `sub` is the exact subject of one repository in one GitHub Environment (`repo:<owner>@<owner id>/<repository>@<repository id>:environment:<name>`). The `demo` environment has a required reviewer, so AWS only issues credentials after the maintainer approved the deployment. This is the reason for choosing OIDC over chaining through a `workforce` role: the gate is visible in the trust, not only in GitHub.

**There is no ExternalId on this role.** `sts:ExternalId` exists only for `AssumeRole`, not for web identity. Its control here is the exact `sub`, which carries the repository and environment IDs, and the environment's own protection. Consequence for the module (IAT-43): it supports two trust modes, `AssumeRole` with the three required conditions and `WebIdentity` with the exact subject, and refuses anything else.

## Archetypes

An **archetype** is a named permission template: the actions allowed with the resource-name patterns they apply to, the explicit denies, and the reason for each. Enabling a repository to deploy a kind of workload into an environment is one instantiation of the role module with that archetype and that repository's subject. An archetype is only ever added, never edited: a change in its permissions is a new decision.

Every archetype shares the structure below, and only the contents of the execution role's policy differ.

- The **deploy role** may do only what is needed to start a CloudFormation deployment: act on stacks named `<key>-<app>-*`, read the artifact, and pass **one** role, `<key>-cfn-exec`, to CloudFormation.
- The **execution role** `<key>-cfn-exec` is what creates the resources. Its policy is the archetype's real permission set. The OIDC identity therefore never holds create rights over application resources, and it cannot create a resource the archetype does not allow.
- A **permissions boundary** `<key>-boundary` caps every role the stack creates for the application (a Lambda execution role, for example), so the application cannot grant itself more than the archetype allows.
- The **agent role** only reads.

The execution role, the boundary and the deploy role are created by the environment account's stack in `workforce-infra`, applied through the gated CI (the order of changes follows the CI-permissions-first rule in `CLAUDE.md`). The application's own resources are created by its pipeline.

## Archetype `lambda`

The reason column is part of the decision: a statement without one is not allowed.

### `<key>-agent` (all environments)

| Allowed | Resource | Reason |
|---|---|---|
| `lambda:GetFunction`, `lambda:GetFunctionConfiguration`, `lambda:GetAlias`, `lambda:ListVersionsByFunction`, `lambda:ListAliases` | functions `<key>-<app>-*` | the agent checks what is deployed, to report on a release and to diagnose |
| `cloudformation:DescribeStacks`, `cloudformation:DescribeStackEvents`, `cloudformation:GetTemplate` | stacks `<key>-<app>-*` | the agent reads a failed deployment |
| `logs:GetLogEvents`, `logs:FilterLogEvents`, `logs:DescribeLogStreams` | log groups `/aws/lambda/<key>-<app>-*` | the agent reads the logs of the code it changed |
| `cloudwatch:DescribeAlarms` | alarms `<key>-<app>-*` | the agent reads the canary and health state |

Opening a release is a GitHub operation and needs nothing in AWS, so the agent role has no write action of any kind.

| Explicitly denied | Reason |
|---|---|
| any `lambda`, `cloudformation`, `logs`, `cloudwatch` write action | the agent proposes changes through pull requests, it does not deploy |
| `iam:*`, `sts:AssumeRole` | no privilege escalation, no role chaining |
| `secretsmanager:*`, `kms:*`, `s3:*` | the agent needs no secret and no data |

The denies are the absence of an Allow plus an account guardrail. They are asserted as calls that must fail (IAT-46) and carry no `Deny` statement, so they cannot lock anyone out.

### `<key>-deploy` (all environments)

| Allowed | Resource | Reason |
|---|---|---|
| `cloudformation:CreateStack`, `UpdateStack`, `DeleteStack`, `CreateChangeSet`, `ExecuteChangeSet`, `DeleteChangeSet`, `DescribeStacks`, `DescribeStackEvents`, `DescribeChangeSet`, `GetTemplate`, `GetTemplateSummary` | stacks `<key>-<app>-*` | start and follow a deployment of this application only |
| `iam:PassRole` | role `<key>-cfn-exec`, condition `iam:PassedToService = cloudformation.amazonaws.com` | CloudFormation needs the execution role, and only that one, to do the work |
| `s3:GetObject` | the artifact prefix of the repository | the deployment reads the artifact built once in CI (`docs/ENVIRONMENTS.md`, build once, promote) |
| `lambda:GetFunction`, `lambda:GetAlias` | functions `<key>-<app>-*` | the post-deploy health check |
| `cloudwatch:DescribeAlarms` | alarms `<key>-<app>-*` | the canary reads the alarm that triggers a rollback |

| Explicitly denied | Reason |
|---|---|
| a stack not named `<key>-<app>-*` | a repository cannot touch another application or the environment's own stack |
| any `iam` action other than the one `PassRole` above | the deploy identity cannot create or change a role, a policy or a user |
| `iam:PassRole` of any other role | no way around the execution role |
| `lambda:*` write actions, directly | resources change only through the stack, so every change is in a template and a change set |
| `organizations:*`, `account:*`, `sts:AssumeRole` | no organization access, no chaining |

### `<key>-cfn-exec` (the real permission set)

| Allowed | Resource | Reason |
|---|---|---|
| `lambda:CreateFunction`, `UpdateFunctionCode`, `UpdateFunctionConfiguration`, `DeleteFunction`, `PublishVersion`, `CreateAlias`, `UpdateAlias`, `DeleteAlias`, `GetFunction`, `GetAlias`, `TagResource`, `UntagResource` | functions `<key>-<app>-*` | the function and its alias, which is what canary shifts weights on |
| `logs:CreateLogGroup`, `DeleteLogGroup`, `PutRetentionPolicy`, `DescribeLogGroups`, `TagResource` | log groups `/aws/lambda/<key>-<app>-*` | retention is set by the stack, so logs do not grow without bound |
| `cloudwatch:PutMetricAlarm`, `DeleteAlarms`, `DescribeAlarms` | alarms `<key>-<app>-*` | the health and rollback alarms |
| `iam:CreateRole`, `DeleteRole`, `AttachRolePolicy`, `DetachRolePolicy`, `PutRolePolicy`, `DeleteRolePolicy`, `GetRole`, `PassRole`, `TagRole` | roles `<key>-<app>-*`, condition `iam:PermissionsBoundary` equal to `<key>-boundary` for the create and attach actions | the function's execution role, only under the naming rule and only with the boundary |
| `s3:GetObject` | the artifact prefix of the repository | `UpdateFunctionCode` reads the package |

| Explicitly denied | Reason |
|---|---|
| a role without the boundary | no way to create an unbounded role |
| `iam` actions on any role outside `<key>-<app>-*`, any `iam` action on users or groups, on the boundary and on `<key>-cfn-exec` itself | the application cannot widen what it may do |
| any resource outside the patterns above | there is no `*` resource in an Allow |
| VPC, EC2, data stores | not part of the `lambda` archetype, a workload that needs them is a new archetype |

### `<key>-boundary`

The permissions boundary lists the actions an application role may ever have: writing its own logs (`logs:CreateLogStream`, `logs:PutLogEvents` on `/aws/lambda/<key>-<app>-*`) and what an archetype's workload needs at runtime, none at first. A role that needs more means a new decision here.

## Narrowing rule: `demo` ⊂ `quality` ⊂ `test`

Narrowing is **set inclusion**, tested mechanically. For a role, take the set of (action, resource pattern) pairs it allows. Then:

> allowed(`demo`) ⊆ allowed(`quality`) ⊆ allowed(`test`)

so any call allowed in `demo` is allowed in `quality` and in `test`, and the reverse is not true. Each step removes capabilities, never swaps them. The agent role is identical in the three environments (read only) and satisfies the rule with equality. For the `lambda` archetype the difference is in the stack actions of `<key>-deploy`:

| Capability | `test` | `quality` | `demo` |
|---|---|---|---|
| `cloudformation:CreateStack`, `DeleteStack` | allowed | no | no |
| `cloudformation:UpdateStack`, change sets | allowed | allowed | allowed |
| `lambda:GetFunction`, `GetAlias`, `cloudwatch:DescribeAlarms`, `s3:GetObject` | allowed | allowed | allowed |

`test` deploys every pull request, so it creates and deletes ephemeral stacks. `quality` and `demo` only update a stack that already exists. That stack is created, once, by the environment account's own stack through the gated CI, which is also what removes a stack: a deployment cannot delete the environment it runs in. `<key>-cfn-exec` follows the same rule for create and delete actions on the function and the alias.

The matrix is a table on purpose: IAT-44 and IAT-45 assert the inclusion with `terraform test`, and IAT-46 derives from each cell a call that must succeed or fail.

## Guardrails

- The M2 SCPs apply to the Environments OU. Nothing here loosens them and no SCP is added.
- No `*` principal, no `*` or `service:*` action, no `NotAction`, `NotPrincipal` or `NotResource` in an Allow, as in `CLAUDE.md`.
- `<key>-boundary` is a permissions boundary, and a boundary can lock a role out. It, and any `Deny` added by the implementation, needs the maintainer's explicit approval in review. A `Deny` may use a wildcard only when it is narrowed by a `Condition` or by specific resources, and it is asserted literally in a test.

## How later issues use this

| Issue | Takes from this document |
|---|---|
| IAT-43 cross-account role module | the two trust modes, the invariants (no `*` principal, no `*` action, no `NotAction`, ExternalId required on `AssumeRole`), the naming regexps |
| IAT-44 agent role per environment | the agent table, the principal and the ExternalId scheme |
| IAT-45 deploy role per environment | the deploy and execution tables, `<key>-boundary`, the narrowing table |
| IAT-46 allowed/denied matrix | every Allowed cell as a call that succeeds, every denied row as a call that fails, and every name checked against the regexps |
| IAT-42, IAT-79 CI baselines and GitHub Environments | the OIDC subjects of the deploy roles |

## Open items

- The deploy tool (SAM or CDK) is decided in M7. This model assumes CloudFormation only, and the tool must work with a pre-created execution role and boundary.
- The artifact location (the bucket and prefix named above) is created with the first deployable and written down then, as a placeholder in this document until it exists.
