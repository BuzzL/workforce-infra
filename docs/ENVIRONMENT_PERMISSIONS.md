# Environment permission model

## Context

Workforce reaches the `test`, `quality` and `demo` accounts through narrowly scoped cross-account roles. This document is the decision, taken before any code: which roles exist, who may assume them, what each may do and may not do, and how the permissions narrow along the promotion path (`docs/ENVIRONMENTS.md`). Later issues implement it and do not change it: a new need is a new decision record here.

Scope of the decision:

- **The environment accounts hold applications, not infrastructure that Terraform owns.** A deployable repository (the testbed first) creates and updates its own resources through CloudFormation (a template written by hand or synthesized by CDK, with no transform, see "Templates" below), in its own pipeline. `workforce-infra` provides only the *access*: the roles below. It never owns an application's function, queue or service.
- **The first workload is serverless, Lambda with an alias,** because it costs nothing to maintain. The model is a catalogue of **archetypes** so that another repository with the same kind of workload is enabled by instantiating a template, not by writing a policy. Further archetypes (`ecs-service`, `ecs-task`) are future sections of this document.
- Placeholders only. No account IDs, emails or ARNs are written here (`scripts/check-docs-public.sh` enforces it).

## Naming rule

Every resource these roles create or may touch is named

> `<acct>-<project>-<name>-<resource>`

in this order, with hyphens between the parts:

| Part | Content | Rule |
|---|---|---|
| `<acct>` | the four-letter **key** of the account the resource lives in (`test`, `qual`, `demo`, from `scripts/environment-keys.tsv`) | always the first four characters |
| `<project>` | the project the resource belongs to: a short name chosen by the maintainer, registered below and mapped to a Linear project (today `foundation`, the basic AWS setup of the Linear project "AI Workforce"). Other projects are not excluded | lowercase letters and digits, `^[a-z0-9]{1,10}$` |
| `<name>` | what the resource belongs to or does: `agent`, or a registered application (`testbed`) followed by a qualifier (`testbed-main`) | lowercase letters and digits, hyphens between segments |
| `<resource>` | the type of the resource, last | one word from a closed list: `role`, `policy`, `boundary`, `stack`, `function`, `alarm` |

A key is never accepted where a name is expected (`docs/ENVIRONMENTS.md`).

### Scope

The strict regexps and the IAM guarantees below apply to the **environment accounts** (`test`, `qual`, `demo`). Other accounts use the same form with their own key and the same word list, and are not covered by these guarantees: `wrkf-<project>-<name>-<resource>` in `workforce`, `scrt-...` in `security`. A resource that lives in `workforce` but serves an environment carries that environment as a name segment, for example the ExternalId secret of `qual`, so the slot always means the account where the resource lives.

Exempt, because the name is not ours to choose: Organizations resources (OUs, accounts, SCPs), Identity Center permission sets (32 characters), and names a service generates. **Existing resources are renamed** to this convention, see "Renaming what exists" below. Nothing keeps its old name by exception.

**One region.** IAM names are global, so this convention holds for one region, as decided in `docs/ORGANIZATION_INPUTS.md`. A second region is a new decision that puts the region in the global names.

### Projects, applications and qualifiers

A project has a short name, registered here with the Linear project it belongs to and what it covers. The short name need not equal the Linear project's name. Everything this repository creates for it carries that name in the second slot and in the `Project` tag (`docs/TAG_CONVENTION.md`). An application belongs to exactly one project.

| Project | Linear project | Covers |
|---|---|---|
| `foundation` | AI Workforce | the basic AWS setup: organization, accounts, access, CI roles, and the roles to deploy into the environment accounts |

An application name is one segment, `^[a-z0-9]{1,16}$`, registered in the table below, unique within its project, and never one of the reserved names `agent`, `platform`, `infra` and `github`. The `<qualifier>` is one or more segments that tell resources of the same type apart (`main`, `api`), at least one is required, and `<app>-<qualifier>` is at most 39 characters. With the longest prefix, a 10-character project (`qual-` plus 10 plus `-`, 16 characters), and the longest suffix `-function` (9), a function name is then at most 64 characters (16 + 39 + 9), which is the limit of IAM role and Lambda function names. A future application whose name would contain a hyphen (`testbed-api`) is a qualifier, never an application.

| Application | Project | Repository | Archetype | Stacks |
|---|---|---|---|---|
| `testbed` | `foundation` | `workforce-testbed` | `lambda` | `main` |

Adding an application is one row here plus one instantiation per environment. The **Stacks** column lists its stack qualifiers: `quality` and `demo` allow exactly those stacks, `test` any stack of the application (see the deploy role).

### Two regexps

Resources the application creates, with its qualifier (PCRE, because the last rule needs a lookahead):

```
^(test|qual|demo)-<project>-[a-z0-9]{1,16}(-[a-z0-9]+)+-(role|policy|stack|function|alarm)$
```
with the extra rules that `<app>-<qualifier>` is at most 39 characters (checked by the matrix script, the regexp does not encode it) and that its `<name>` does not start with a reserved name (`agent`, `platform`, `infra`, `github`) and does not end in `-deploy`, `-exec` or `-boundary`, which the platform regexp owns.

Platform resources, enumerated exactly (the roles of the CI baselines (`infra`, `github`) live in the account of their key, so the account slot also admits `root`, `wrkf` and `scrt` here):

```
^(test|qual|demo|root|wrkf|scrt)-<project>-(agent-role|infra-role|infra-plan-role|github-role|github-plan-role|[a-z0-9]{1,16}-(deploy-role|exec-role|boundary))$
```

The Lambda alias is the one resource with a fixed name, `live`: it is scoped by its function, so a prefix adds nothing. The log group of a function is named after it, `/aws/lambda/<function name>`.

The allowed/denied matrix script asserts that every name in a policy matches one of the two regexps, that its application is registered, and the length limits. The word of a name is not proof of its type: a policy pattern also names the service in the ARN, so a function called `...-role` is not reachable through a role pattern.

### Platform resources and paths

| Resource | Name | IAM path |
|---|---|---|
| Agent role (one per environment, shared) | `<acct>-<project>-agent-role` | `/platform/` |
| CI roles of the baselines (apply, plan) | `<acct>-<project>-infra-role`, `<acct>-<project>-infra-plan-role`, and for the CI of `workforce-github` `root-<project>-github-role`, `root-<project>-github-plan-role` | `/platform/` |
| Permissions boundary (one per application) | `<acct>-<project>-<app>-boundary` | `/platform/` |
| Deploy role (one per application) | `<acct>-<project>-<app>-deploy-role` | `/platform/` |
| CloudFormation execution role (one per application) | `<acct>-<project>-<app>-exec-role` | `/platform/` |
| IAM role an application creates | `<acct>-<project>-<app>-<qualifier>-role` | `/apps/<app>/` |

**Platform and application roles are told apart by the IAM path,** and each application has a path of its own. The execution role may create and pass roles only under `/apps/<app>/` with the application's prefix, so it can never reach `/platform/` roles (the deploy role, itself, the agent role, the boundary) or another application's roles, and a `*` in a pattern cannot be used to put a role on another application's path. Role names are unique per account whatever the path, so an application cannot create a role named like a platform role: the call fails with `EntityAlreadyExists`.

Each application has **its own deploy role, execution role and boundary**: the deploy role of one application can pass only its own execution role, whose policy covers only its own resources, so one repository cannot reach another's.

**What IAM does not enforce.** In a policy pattern `*` also matches `/`, `:` and the empty string, so inside one application IAM cannot force the `<qualifier>` or the type word (`.../testbed-x/...` or `testbed--role` would match). The name rule inside an application is enforced by the template lint and by a check of the matrix script that lists the application's resources after a deployment and matches them against the regexps. IAM enforces the account, the application and the path.

### ARN shapes

Policy patterns are full ARNs, because that is what IAM matches. The shapes the `lambda` archetype uses (`<region>` and `<account>` are the environment's, written as placeholders):

| Resource | ARN resource part |
|---|---|
| Stack | `stack/<acct>-<project>-<app>-*-stack/*` (the trailing part is a GUID) |
| Function | `function:<acct>-<project>-<app>-*-function` and, for aliases and versions, `function:<acct>-<project>-<app>-*-function:*` |
| Alarm | `alarm:<acct>-<project>-<app>-*-alarm` |
| Log group | `log-group:/aws/lambda/<acct>-<project>-<app>-*-function` and `...:*` |
| Log stream | `log-group:/aws/lambda/<acct>-<project>-<app>-*-function:log-stream:*` |
| Application role | `role/apps/<app>/<acct>-<project>-<app>-*-role` |
| Platform role, boundary, policy | `policy/platform/<acct>-<project>-<app>-boundary` and `role/platform/<name>` with the exact names above |

Tags are a complement and never a control on their own: `docs/TAG_CONVENTION.md`.

## Renaming what exists

The resources created before this decision are renamed to it, and their tags migrated (`docs/TAG_CONVENTION.md`). The mapping, in the account where each one lives:

| Today | Becomes | Note |
|---|---|---|
| `github-infra-<account name>` (CI apply role of a member account) | `<acct>-<project>-infra-role`, for example `wrkf-<project>-infra-role` | the key of that account |
| `github-infra-<account name>-plan` | `<acct>-<project>-infra-plan-role` | |
| `github-infra-management`, `github-infra-management-plan` | `root-<project>-infra-role`, `root-<project>-infra-plan-role` | |
| `github-infra-github`, `github-infra-github-plan` | `root-<project>-github-role`, `root-<project>-github-plan-role` | the CI of `workforce-github` |
| the Terraform state bucket, the audit log bucket | named by the S3 decision (see "Next decisions"), then renamed | a bucket cannot be renamed: it is replaced and its objects moved, so it is its own change |
| the `Project`, `ManagedBy`, `Stack` tags | the keys and values of `docs/TAG_CONVENTION.md` | in place |

How, because a CI role cannot rename itself and a name is part of its ARN:

1. One role at a time, in its own PR, **new role first**. In order: (a) the CI role's permissions allow creating the new name and path (CI-permissions-first, `CLAUDE.md`); (b) create the new role with the same permissions and trust; (c) the state bucket policy, applied locally from `bootstrap/`, carries **both** ARNs; (d) switch the GitHub Environment secrets that hold the ARN and ID (`AWS_ROLE_ARN`, `AWS_ROLE_ID`) and every trust that names the role; (e) a real run assumes the new role and reaches the state through the bucket policy, which proves the ARN form (an assumed role's ARN may not carry the path); (f) only then delete the old role and its ARN in the bucket policy, in a later PR.
2. Both roles may exist until that later PR, but only one is in use at any time. A step that fails before (d) leaves the old role working, so a rename is a failure at worst, never a lockout.
3. The IAM paths of the convention (`/platform/` for platform roles) apply to the new roles. The roles of the baselines are platform roles.
4. Each rename is proven by a no-op plan afterwards, and by the first CI run that assumes the new role.

## Templates

CloudFormation names an unnamed resource `<stack>-<LogicalId>-<RANDOM>`, in mixed case, which no pattern above matches, and a policy that fails closed turns that into `AccessDenied` at the first deploy. So the `lambda` archetype requires, and a template lint in the application's CI (cfn-lint or cfn-guard, a required check) enforces:

- every named resource sets its **explicit name**, an IAM role also its **path** `/apps/<app>/` and its **permissions boundary**, and the stack is deployed with `CAPABILITY_NAMED_IAM`;
- the function declares its own **log group**, with retention, rather than leaving Lambda to create it. The execution role may create the log group and the function's role may not (it only writes streams);
- **no `Transform`**. A SAM template needs the transform resource in every change set and creates default-named resources, so SAM is a new decision, not an option of this archetype;
- no nested stacks and no custom resources (the CDK log-retention helper, for one), which create resources named outside the rule;
- the CDK default bootstrap (`cdk-*` roles, bucket and SSM parameter) is not used: the deployment is the artifact built once in CI, the pre-created execution role and the stack tags of `docs/TAG_CONVENTION.md`.

## Roles and trust

| Role | Used by | Trust |
|---|---|---|
| `<acct>-<project>-agent-role` | the developer agent (ECS task in `workforce`) | `sts:AssumeRole` |
| `<acct>-<project>-<app>-deploy-role` | the deploy job of the application repository | `sts:AssumeRoleWithWebIdentity` (GitHub OIDC) |
| `<acct>-<project>-<app>-exec-role` | CloudFormation, when it deploys a stack of the application | `sts:AssumeRole` by the service `cloudformation.amazonaws.com` |

### Agent role: `sts:AssumeRole` from `workforce`

The trust policy names one principal, the agent task role in the `workforce` account, by exact ARN (`aws:PrincipalArn`), and requires all of:

- the source account, through the principal (no `*` principal, no account root);
- `sts:ExternalId`, equal to the environment's ExternalId;
- `sts:RoleSessionName` `StringLike` `agent-*`, so that CloudTrail attributes a session to an agent task. The task names its session `agent-<task id>`.

**Where the ExternalId lives.** One value per environment, generated once by the maintainer and written to two places by a script: a Secrets Manager secret in the `workforce` account, readable by the agent task role only, which is what the agent uses; and a secret of the GitHub Environment of the environment account's stack, which Terraform alone reads, as a sensitive variable, to write the trust policy. The agent never reads GitHub and Terraform never reads Secrets Manager. Neither copy is authoritative: a rotation updates both, and a mismatch fails closed (the assume is denied). Sensitive values still reach the Terraform state, which is acceptable because the ExternalId is not a credential: it prevents the confused-deputy case, the access control is the principal ARN. It is never in the repo or in logs (`scripts/redact.sh`).

**Rotation.** Create the new value, apply the role with both values accepted, switch the secret in `workforce`, apply again with the old value removed. Every step is a reviewed change.

### Deploy role: GitHub OIDC, one subject per GitHub Environment

The trust policy is the pattern of `modules/account-ci-baseline`: the account's GitHub OIDC provider, `StringEquals` (never `StringLike`) on `aud` and on `sub`, where `sub` is the exact subject of one repository in one GitHub Environment (`repo:<owner>@<owner id>/<repository>@<repository id>:environment:<name>`). The `demo` environment has a required reviewer, so AWS only issues credentials after the maintainer approved the deployment. This is the reason for choosing OIDC over chaining through a `workforce` role: the gate is visible in the trust, not only in GitHub.

**The `sub` carries the environment but no ref.** The branch restriction is therefore a **precondition** held by the GitHub Environment, not by AWS: `test` accepts `feature/*` and `bugfix/*`, `quality` only `main`, `demo` only `v*` tags (`docs/ENVIRONMENTS.md`, in `workforce-github`). Without it, any workflow naming the environment could assume the role. The GitHub Environment settings are checked where they are defined (`workforce-github`).

**There is no ExternalId on this role.** `sts:ExternalId` exists only for `AssumeRole`, not for web identity. Its control here is the exact `sub`, which carries the repository and environment IDs, and the environment's own protection. Consequence for the role module: it supports two trust modes, `AssumeRole` with the three required conditions and `WebIdentity` with the exact subject, and refuses anything else.

### Execution role: the CloudFormation service

The trust policy names one principal, the service `cloudformation.amazonaws.com`, and requires `aws:SourceAccount` equal to the account itself and `aws:SourceArn` like the stacks of its own application (`stack/<acct>-<project>-<app>-*-stack/*`), so that only CloudFormation acting for that application's stacks can use it (confused deputy). It lives under `/platform/`, has no boundary of its own (its own policy is the permission set), and cannot be assumed by a person or an agent.

## Archetypes

An **archetype** is a named permission template: the actions allowed with the resource-name patterns they apply to, the narrowing per environment, and the reason for each. Enabling a repository to deploy a kind of workload into an environment is one instantiation of the role module with that archetype and that repository's subject. An archetype is only ever added, never edited: a change in its permissions is a new decision.

- The **deploy role** may do only what is needed to start a CloudFormation deployment: act on stacks named `<acct>-<project>-<app>-*-stack`, read the artifact, and pass **one** role, its own `<acct>-<project>-<app>-exec-role`, to CloudFormation.
- The **execution role** creates the resources. Its policy is the archetype's real permission set. The OIDC identity therefore never holds create rights over application resources.
- The **permissions boundary** `<acct>-<project>-<app>-boundary`, one per application, caps every role a stack creates for that application, so it cannot grant itself more than the archetype allows and cannot touch another application's logs.
- The **agent role** only reads.

The agent and deploy roles are created by the environment account's baseline stack in `workforce-infra`, applied locally because the CI apply role has no IAM write (`docs/AGENT_ROLES.md`, `docs/DEPLOY_ROLES.md`). The execution role and the boundary follow the same rule unless the CI permissions are widened first (the CI-permissions-first rule in `CLAUDE.md`). The application's resources are created by its pipeline.

**Bootstrap and recovery are the maintainer's, not a role's.** The first creation of an application's stack in `quality` and `demo`, and the recovery of a stack stuck in `CREATE_FAILED` or `ROLLBACK_COMPLETE` (which can only be deleted), are done by the maintainer from the SSO admin session, like the account baselines (`docs/ACCOUNT_CI_BASELINES.md`), and noted in the Linear issue. No role in `quality` or `demo` can delete a stack, or create one under a name that is not registered for the application. `test` can do both, because its stacks are ephemeral. The one gap IAM cannot close: a registered stack that the maintainer has deleted could be recreated by the deploy role, still bound to its execution role, its template location and the stack tags (in `demo` the execution role cannot create the resources, so the recreation fails). So the recovery step begins by removing the stack's qualifier from the Stacks column and ends by putting it back.

## Archetype `lambda`

The reason column is part of the decision: a statement without one is not allowed. Rows headed "Not allowed" are the **absence of an Allow** or an Allow narrowed by a condition. None of them is a `Deny` statement, so none can lock a principal out. They are asserted as calls that must fail, by the allowed/denied matrix script.

**Resource `*` exception.** Two read-only actions need `Resource: "*"`, listed in the tables as "(resource `*`)": `logs:DescribeLogGroups`, which has no resource type at all, and `cloudformation:GetTemplateSummary` when it is called with a template URL, because there is no stack to name (it is narrowed by `cloudformation:TemplateUrl` to the artifact prefix). Nothing else has a `*` resource. `CLAUDE.md` forbids `*` actions and principals, not a `*` resource, but a resource wildcard is still a widening, so it needs the maintainer's approval in this review.

**Verified against the AWS service authorization reference** (Service Reference data, 2026-10-02), which this document relies on: `cloudformation:CreateChangeSet`, `CreateStack`, `UpdateStack`, `DeleteStack` take `cloudformation:RoleArn` (written `RoleArn`), `ExecuteChangeSet` does not; `CreateChangeSet`, `CreateStack`, `UpdateStack` take `cloudformation:TemplateUrl`; all stack actions are resource-level on `stack`; `cloudwatch:DescribeAlarms`, `PutMetricAlarm`, `DeleteAlarms` are resource-level on `alarm`; `logs:GetLogEvents` is resource-level on `log-stream` and `DescribeLogStreams`, `FilterLogEvents`, `CreateLogGroup`, `DeleteLogGroup`, `PutRetentionPolicy` on `log-group`. **The condition key `cloudformation:ChangeSetType` does not exist**, so a rule cannot tell a `CREATE` change set from an `UPDATE` one: creating a stack under an unregistered name is prevented in `quality` and `demo` by the resource instead (see the deploy role). 

**No secrets in function configuration.** Environment variables of a function carry names and endpoints, never secrets (a secret is referenced by its Secrets Manager name and read at runtime). This is what lets the agent read configuration.

### `<acct>-<project>-agent-role` (identical in all environments)

| Allowed | Resource | Reason |
|---|---|---|
| `lambda:GetFunctionConfiguration`, `lambda:GetAlias`, `lambda:ListVersionsByFunction`, `lambda:ListAliases` | functions (and their aliases) `<acct>-<project>-<app>-*-function` | the agent checks what is deployed. `GetFunction` is left out: it returns a pre-signed URL to the code package |
| `cloudformation:DescribeStacks`, `DescribeStackEvents` | stacks `<acct>-<project>-<app>-*-stack` | the agent reads a failed deployment. `GetTemplate` is left out: templates may name internal resources |
| `logs:FilterLogEvents`, `logs:DescribeLogStreams` | log groups `/aws/lambda/<acct>-<project>-<app>-*-function` | the agent reads the logs of the code it changed |
| `logs:GetLogEvents` | log streams of those log groups | same (this action is resource-level on the stream, not the group) |
| `cloudwatch:DescribeAlarms` | alarms `<acct>-<project>-<app>-*-alarm` | the agent reads the canary and health state |

Opening a release is a GitHub operation and needs nothing in AWS, so the agent role has no write action of any kind.

| Not allowed | Reason |
|---|---|
| any `lambda`, `cloudformation`, `logs`, `cloudwatch` write action | the agent proposes changes through pull requests, it does not deploy |
| `iam:*`, `sts:AssumeRole` | no privilege escalation, no role chaining |
| `secretsmanager:*`, `kms:*`, `s3:*`, `lambda:GetFunction` | the agent needs no secret, no data and no code download |

### `<acct>-<project>-<app>-deploy-role`

| Capability | Resource | `test` | `quality` | `demo` | Reason |
|---|---|---|---|---|---|
| `cloudformation:CreateStack`, `DeleteStack` | stacks `<acct>-<project>-<app>-*-stack` | yes | no | no | `test` deploys every pull request, so it creates and deletes ephemeral stacks |
| `cloudformation:CreateChangeSet` | stacks `<acct>-<project>-<app>-*-stack` in `test`; **exactly the registered stacks** (`<acct>-<project>-<app>-<qualifier>-stack` for each qualifier of the Stacks column) in `quality` and `demo` | yes | yes | yes | the only way a change is made. A change set can also create a stack, and no condition key separates the two, so in `quality` and `demo` the resource is the control: a name that is not registered is outside it, and a registered one already exists. Only a registered stack that was deleted could be recreated, see "Bootstrap and recovery". Carries `cloudformation:RoleArn` and `cloudformation:TemplateUrl` below |
| `cloudformation:ExecuteChangeSet`, `DeleteChangeSet`, `DescribeStacks`, `DescribeStackEvents`, `DescribeChangeSet`, `GetTemplate` | same stacks as the row above: the pattern in `test`, exactly the registered ones in `quality` and `demo` | yes | yes | yes | follow and finish a deployment of this application only |
| `cloudformation:GetTemplateSummary` (resource `*`), condition `cloudformation:TemplateUrl` under the artifact prefix | | yes | yes | yes | reads the template before a change set |
| `cloudformation:TagResource`, `UntagResource` | same | yes | yes | yes | the stack tags of `docs/TAG_CONVENTION.md`, only those keys (`aws:TagKeys`). A stack cannot be created without them: `aws:RequestTag` equals the literals for `App` and `Environment` |
| `iam:PassRole` of `<acct>-<project>-<app>-exec-role`, condition `iam:PassedToService` = `cloudformation.amazonaws.com` | that one role | yes | yes | yes | CloudFormation needs the execution role, and only that one |
| `s3:GetObject` | the artifact prefix of the repository | yes | yes | yes | the deployment reads the artifact built once in CI (`docs/ENVIRONMENTS.md`) |
| `lambda:GetFunctionConfiguration`, `lambda:GetAlias` | functions `<acct>-<project>-<app>-*-function` | yes | yes | yes | the post-deploy health check |
| `cloudwatch:DescribeAlarms` | alarms `<acct>-<project>-<app>-*-alarm` | yes | yes | yes | the canary reads the alarm that triggers a rollback |

| Not allowed | Reason |
|---|---|
| `CreateStack`, `CreateChangeSet` or `DeleteStack` without `cloudformation:RoleArn` equal to the application's execution role, or `CreateChangeSet` or `CreateStack` with a `cloudformation:TemplateUrl` outside the artifact prefix | every change goes through a change set, with the one role and the one artifact |
| a stack not named `<acct>-<project>-<app>-*-stack` | a repository cannot touch another application or the environment's own resources |
| any `iam` action other than the one `PassRole` above | the deploy identity cannot create or change a role, a policy or a user |
| `iam:PassRole` of any other role, including another application's | no way around the execution role |
| `lambda:*` write actions, directly, and `cloudformation:UpdateStack` | resources change only through a change set, so every change is in a template and reviewable |
| `organizations:*`, `account:*`, `sts:AssumeRole` | no organization access, no chaining |

### `<acct>-<project>-<app>-exec-role` (the real permission set)

Resources are the application's, `<acct>-<project>-<app>-*-<resource>`. Roles are `role/apps/<app>/<acct>-<project>-<app>-*-role`, and the boundary is `<acct>-<project>-<app>-boundary`.

| Capability | `test` | `quality` | `demo` | Reason |
|---|---|---|---|---|
| `lambda:UpdateFunctionCode`, `UpdateFunctionConfiguration`, `PublishVersion`, `UpdateAlias`, `GetFunction`, `GetFunctionConfiguration`, `GetAlias` | yes | yes | yes | releasing a version and moving the alias, which is what a canary shifts weights on |
| `lambda:TagResource`, `UntagResource`, `cloudwatch:TagResource`, `UntagResource`, `logs:TagResource`, `UntagResource`, `iam:TagRole`, `UntagRole` | yes | yes | yes | stack tags are propagated to the resources and are updated with the stack (`docs/TAG_CONVENTION.md`), only the keys of the convention (`aws:TagKeys`) |
| `lambda:ListTags`, `ListVersionsByFunction`, `GetPolicy`, `iam:GetRolePolicy`, `ListRolePolicies`, `ListAttachedRolePolicies`, `logs:ListTagsForResource`, `cloudwatch:ListTagsForResource` | yes | yes | yes | reads CloudFormation does before it updates a resource |
| `lambda:CreateFunction`, `CreateAlias` | yes | yes | no | a resource new to the template is created in `quality` first. `demo` does not create resources: a missing one means a maintainer bootstrap |
| `lambda:DeleteFunction`, `DeleteAlias` | yes | no | no | `quality` and `demo` never destroy |
| `logs:CreateLogGroup`, `PutRetentionPolicy` | yes | yes | no | the log group is declared by the template, with retention, so logs do not grow without bound |
| `logs:DeleteLogGroup` | yes | no | no | never destroy |
| `cloudwatch:PutMetricAlarm` | yes | yes | no | the health and rollback alarms (`demo` changes none) |
| `cloudwatch:DeleteAlarms` | yes | no | no | never destroy |
| `iam:CreateRole`, `AttachRolePolicy`, `PutRolePolicy` | yes | yes | no | the function's execution role, with the boundary |
| `iam:DeleteRole`, `DetachRolePolicy`, `DeleteRolePolicy` | yes | no | no | never destroy |
| `iam:GetRole`, `iam:PassRole` (condition `iam:PassedToService` = `lambda.amazonaws.com`) | yes | yes | yes | read the role, hand it to the function |
| `s3:GetObject` on the artifact prefix | yes | yes | yes | `UpdateFunctionCode` reads the package |
| `logs:DescribeLogGroups` (resource `*`) | yes | yes | yes | CloudFormation checks for an existing log group |

Conditions on the `iam` rows: every one is limited to roles under `role/apps/<app>/<acct>-<project>-<app>-*-role`. Only `CreateRole`, `AttachRolePolicy` and `PutRolePolicy` also require the boundary, compared by its **full ARN** (`iam:PermissionsBoundary`), so an existing unbounded role under the pattern cannot be edited that way. The other `iam` actions (`Detach`, `Delete`, `Tag`) rely on the path and name pattern alone, since the key does not apply to them, and `AttachRolePolicy` is capped by the boundary until the `iam:PolicyARN` decision below. The trust policy of an application role names only `lambda.amazonaws.com`, a template-lint rule: IAM cannot constrain the trust document at `CreateRole`. The control that holds is the boundary, which allows only log writes, so even a role with a wrong trust can do nothing else. `iam:UpdateAssumeRolePolicy` is not allowed, so the trust is set at creation.

| Not allowed | Reason |
|---|---|
| `iam:PutRolePermissionsBoundary`, `DeleteRolePermissionsBoundary`, `UpdateAssumeRolePolicy` | the application cannot remove or swap its cap, or open its trust |
| a role without the boundary, any role outside `role/apps/<app>/<acct>-<project>-<app>-*-role` | no way to create an unbounded role. The `/platform/` roles, the boundary and the execution role itself are out of reach because of the path, and another application's roles because of its own path |
| any `iam` action on users or groups | not part of the archetype |
| any resource outside the patterns above | there is no `*` resource in an Allow except the exception above |
| `lambda:AddPermission` and event sources, layers (`lambda:PublishLayerVersion`, any layer on a function), VPC, EC2, data stores, CodeDeploy | not part of the `lambda` archetype, so no function is invocable by another principal. Layers are a lint rule. A workload that needs them, or canary through CodeDeploy, is a new archetype. This one shifts weight on the alias through `UpdateAlias` |

### `<acct>-<project>-<app>-boundary`

The permissions boundary lists the actions an application role may ever have: writing the streams of its own function's log group (`logs:CreateLogStream`, `logs:PutLogEvents` on `/aws/lambda/<acct>-<project>-<app>-*-function`) and what the workload needs at runtime, none at first. It has no `logs:CreateLogGroup`: the group is declared by the template. A role that needs more means a new decision here. The execution role compares `iam:PermissionsBoundary` with the full ARN of this application's boundary.

## Narrowing rule: `demo` ⊂ `quality` ⊂ `test`

Narrowing is **set inclusion**, tested mechanically. For a role, take the set of (action, resource pattern) pairs it allows. Then:

> allowed(`demo`) ⊆ allowed(`quality`) ⊆ allowed(`test`)

so any call allowed in `demo` is allowed in `quality` and in `test`, and the reverse is not true. Each step removes capabilities and never swaps them. The agent role is identical in the three environments (read only) and satisfies the rule with equality. The columns above are the decision. The execution role narrows properly at both steps. The deploy role narrows properly from `test` to `quality` and is equal in `quality` and `demo` (what differs there is the trust: `demo` needs the reviewer's approval, and the execution role below it cannot create or delete anything):

- `test` → `quality`: no stack creation or deletion by action, the stacks narrow from a pattern to the registered list, and no deletion of any resource. Stacks are only updated, and a new resource arrives in a change set of a registered stack.
- `quality` → `demo` (execution role): no creation of any resource, as well. `demo` only updates what already exists, so a release cannot grow or shrink the demo account's footprint without the maintainer.

The consequence is deliberate: an artifact that adds a resource runs in `quality` first, and `demo` needs a maintainer bootstrap step for that resource before the release. Removing a resource leaves it in place until the maintainer cleans it up.

The matrix is a table on purpose: the module tests assert the inclusion with `terraform test`, and the matrix script derives from each cell a call that must succeed or fail.

## Guardrails

- The M2 SCPs apply to the Environments OU. Nothing here loosens them and no SCP is added.
- No `*` principal, no `*` or `service:*` action, no `NotAction`, `NotPrincipal` or `NotResource` in an Allow, as in `CLAUDE.md`.
- The permissions boundary `<acct>-<project>-<app>-boundary` can lock a role out. It, the `Resource: "*"` exception above, and any `Deny` added by the implementation, need the maintainer's explicit approval in review. This decision introduces no `Deny` statement. A `Deny` may use a wildcard only when it is narrowed by a `Condition` or by specific resources, and it is asserted literally in a test.

## How the implementation uses this

| Part | Takes from this document |
|---|---|
| Cross-account role module | the two trust modes (and the execution role's service trust), the invariants (no `*` principal, no `*` action, no `NotAction`, ExternalId required on `AssumeRole`), the two naming regexps, the length limits and the IAM paths |
| Agent roles | the agent table, the principal and the ExternalId scheme |
| Deploy and execution roles | the deploy and execution tables (per application), the per-application boundary, the narrowing steps, the template rules |
| Allowed/denied matrix script | every Allowed cell as a call that succeeds, every denied row as a call that fails, and every name checked against the regexps |
| CI baselines and GitHub Environments | the OIDC subjects of the deploy roles and the branch and tag restrictions of the GitHub Environments |

## Open items

- The artifact location (the bucket and prefix named above) is created with the first deployable and written down then, as a placeholder in this document until it exists.
- SAM is not part of the `lambda` archetype (transform). It would be a new archetype or a new decision.
- `cloudwatch:DescribeAlarms` is resource-level in the reference, but a query by alarm-name prefix or without names may still need `*` in practice. The matrix script proves the exact call the canary makes with a real call, and the tables change only if it fails.
- The function's environment variables carry no secret: a lint rule, like the trust of application roles.

## Next decisions

Decided when the first resource of the kind exists, not guessed now. Each is a new section here, never an edit above.

- **More resource types:** the S3 artifact bucket (global names, 63 characters, a name that cannot be guessed in a public repository), Secrets Manager and SSM parameters (hierarchical names, `<acct>/<project>/<app>/<key>`), KMS aliases, SQS (`.fifo` ends a name), EventBridge, ECS (task definition ARNs end in `:*`). Each with its ARN shape, length limit and word, kept in a table next to `scripts/environment-keys.tsv`, which the matrix script also reads.
- `iam:PolicyARN` on `AttachRolePolicy`, so that an application role can only be given policies from a list.
- Whether `aws:PrincipalArn` carries the IAM path for the agent task role in `workforce`: prove it with one real call, or give that role no path, before the agent roles are built.
- Policy size: the agent role grows with every application, and the trust policy holds two ExternalIds during a rotation. Check against the IAM limits when the second application is added.
