# Tag convention

## Context

Every taggable AWS resource of the workforce carries the same small set of tags. Names say what a resource is (`docs/ENVIRONMENT_PERMISSIONS.md`, naming rule). Tags say who owns it and where it comes from, so that cost, ownership and drift can be read without parsing a name, including for resources whose names this repository cannot control (KMS keys, S3 buckets, resources named by a service).

This is a decision record. Implementations follow it without changing it. Placeholders only: no account IDs, emails or ARNs.

## Principles

1. **Tags describe, names authorize.** Access control rests on names, paths and ARNs. A tag may be an *additional* condition on a create (`aws:RequestTag/<key>` equal to a literal). A tag is never the only thing an Allow depends on, and `aws:ResourceTag` is not used to authorize unless `TagResource` and `UntagResource` are themselves constrained by `aws:TagKeys` and the same condition. Anyone who can retag a resource can otherwise change its authorization.
2. **Same keys everywhere.** One key set for every account, repository and tool. A resource that cannot carry a tag is listed in the exceptions below.
3. **Set where the resource is declared, once.** Not by hand, and not duplicated per resource.
4. **Values are bounded.** They come from a closed list or a pattern, so they can be checked with a strict regexp.

## Keys

Keys are PascalCase, a single word, case-sensitive, and never start with `aws:` (reserved). This is the style already used by the stacks (`Project`, `ManagedBy`, `Stack`).

| Key | Required | Value | Pattern | Meaning |
|---|---|---|---|---|
| `Project` | yes | `workforce` | `^workforce$` | the project, the same word as in resource names |
| `Environment` | yes | the **name** of the account the resource lives in: `management`, `security`, `workforce`, `test`, `quality`, `demo` | one of the names in `scripts/environment-keys.tsv` | where it runs. The name, not the four-letter key: a key is never accepted where a name is expected (`docs/ENVIRONMENTS.md`) |
| `App` | yes | `agent`, `platform`, or a registered application (`testbed`) | `^[a-z0-9]{1,16}$` | what the resource belongs to. Matches the application segment of its resource name where it has one; `platform` is for shared infrastructure that belongs to no application |
| `Repository` | yes | the repository that holds that code, without owner | `^workforce-[a-z]+$` | where to change it. Together with `ManagedBy` and `Stack` it is the full pointer: repository, technology, unit of deployment |
| `ManagedBy` | yes | the **technology** whose code is the source of truth: `terraform`, `cdk`, `cloudformation` (a hand-written template) or `manual`; `sam` is reserved (the `lambda` archetype has no transform, `docs/ENVIRONMENT_PERMISSIONS.md`) | closed list | what to run to change it. It names the tool the code is written in, not the engine: a CDK or SAM stack is deployed by CloudFormation but is `cdk` or `sam`. `manual` is for break-glass and bootstrap and needs a note in the Linear issue |
| `Stack` | yes | the Terraform root stack path (`live/management`) or the CloudFormation stack name | `^[A-Za-z0-9/_-]{1,128}$` | which unit of deployment owns it |
| `Archetype` | for applications | `lambda`, and later `ecs-service`, `ecs-task` | closed list | the workload archetype of the application |
| `Target` | when different from `Environment` | the **name** of the environment the resource serves, for resources that live in another account | same as `Environment` | for example the ExternalId secret of `quality`, which lives in `workforce`: `Environment=workforce`, `Target=quality` |

Reading the three together: `Repository=workforce-infra`, `ManagedBy=terraform`, `Stack=live/management` means "change `live/management` in `workforce-infra` with Terraform". A new technology (for example Pulumi) is a new value in the list, added here first.

Rules for values:

- lowercase letters, digits and hyphens, except `Stack` (path characters) and `Repository`;
- no account IDs, emails, ARNs, ticket text or free text. AWS limits: key 128 characters, value 256, 50 tags per resource;
- a value that changes meaning (renaming an application) is a migration, not an edit.

Not used on purpose: a ticket or PR number (it changes and invites drift), an owner's name or email (public repo), a version or commit (a deployment fact, not an identity), and a `Name` tag (the resource name already exists).

## How the tags are applied

| Where | Mechanism |
|---|---|
| Terraform stacks | `default_tags` of every AWS provider block, fed by the `tags` variable. Modules also take `tags` for the resources the provider cannot default-tag (`aws_iam_role_policies_exclusive`, resources created by services). One provider block per stack, so one place |
| CDK / SAM / CloudFormation (application repositories) | stack tags, which CloudFormation propagates to the stack's resources, with `ManagedBy` set to `cdk` or `cloudformation`. The deploy role may set only these keys (`aws:TagKeys`) and must set `App` and `Environment` to their literals at `CreateStack` (`docs/ENVIRONMENT_PERMISSIONS.md`), and the stack's tags are fixed by the pipeline, not the template |
| Manual (break-glass, bootstrap) | the same tags, `ManagedBy=manual`, added before the issue is closed |
| Resources a service creates itself (CloudTrail log delivery, auto-created log groups) | not tagged. They are declared explicitly where it matters (`docs/ENVIRONMENT_PERMISSIONS.md`, explicit names) so that they can be tagged |

## Exceptions

A resource that does not support tags is not tagged and is covered by its name and by the stack that declares it. The list is kept here: Lambda aliases and versions, log streams and change sets (so `Archetype` is moot for them, the function carries it). IAM OIDC providers support tags and are tagged. A new exception is a line in this document with the reason.

GitHub resources have no tags. The equivalent is the repository **topic** `ai-workforce` (`workforce-github`), plus the `workforce-<role>` name.

## Using tags

- **Cost.** `Project`, `Environment` and `App` are activated as cost allocation tags in the management account, which takes effect for charges from the activation date. A tag must exist on a resource before it can be activated, so the activation follows the migration PR. This is a billing setting of the management account and is made together with the budget (`docs/BUDGET.md`).
- **IAM.** Application roles may be created only with a literal tag where this adds a second control, for example `aws:RequestTag/App` equal to the application on `CreateRole` and `CreateFunction`. A tag condition never replaces the name and path conditions.
- **Operations.** Find everything an application owns with `Project` plus `App`, or everything a stack owns with `Stack`, for review, for drift and for cleanup.

## Enforcement

- **Terraform:** a gate in `make check` (follow-up) checks that every `provider "aws"` block has `default_tags`, and that the default of the `tags` variable of each stack contains the required keys with values matching the patterns above. `terraform test` asserts the tags of a representative resource per module.
- **CloudFormation:** the application pipeline passes the tags as stack tags, and the allowed/denied matrix (IAT-46) proves that the deploy role cannot create a stack without them or retag a resource outside its application.
- **Drift:** tags are managed by their tool. A manual retag shows as a Terraform plan difference.

## Migration of what exists

Existing stacks already tag `Project`, `ManagedBy` and `Stack`.

| Change | Reason |
|---|---|
| `Project`: `ai-workforce` → `workforce` | one word for the project in names and tags. `ai-workforce` stays as the GitHub topic |
| add `Environment`, `App` and `Repository` to every stack | required keys. For the current stacks `App=platform`, `Repository=workforce-infra`, and `Environment` is the name of the account |
| add `Archetype` and `Target` where they apply | optional keys |

Each is one in-place tag update per stack, applied through the gated CI like any other change. It is its own PR after this decision is approved, and it may need tagging actions the CI roles do not hold yet (for example `organizations:TagResource` for OUs and accounts, and the budget): check this first and, if so, update the CI role in its own earlier PR (the CI-permissions-first rule).

## Open items

- Whether `Project` changes to `workforce` (above) or the project word in resource names changes to `ai-workforce`. This record chooses `workforce`, to keep names short (IAM and Lambda names are limited to 64 characters).
- A `DataClassification` tag is not defined: no resource holds data other than state and logs today. Add it with the first resource that does.
