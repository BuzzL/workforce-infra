# CDK bootstrap of the workforce account

The pipeline application (`workforce-pipeline`, M4) is a CDK app deployed into the `workforce` account by its own CI. Terraform holds the access, CDK the application (`docs/ENVIRONMENT_PERMISSIONS.md`, scope). This document says how that deployment gets the least privilege that works: no `AdministratorAccess`, no default `cdk-*` roles, no `*` in an Allow.

## The pieces

All three live in `bootstrap/accounts/workforce/pipeline.tf`, under `/platform/`, and follow the naming rule with the key `wrkf` and the application `pipeline`. They are off until the variable `pipeline` (the numeric GitHub ID of `workforce-pipeline`, public) is set.

| Piece | Name | Who uses it |
|---|---|---|
| Deploy role | `wrkf-foundation-pipeline-deploy-role` | the CI of `workforce-pipeline`, through GitHub OIDC |
| CloudFormation execution role | `wrkf-foundation-pipeline-exec-role` | CloudFormation, passed by the deploy role |
| Permissions boundary | `wrkf-foundation-pipeline-boundary` (managed policy) | every role the pipeline's stacks create |

### Deploy role

Trust: web identity, `StringEquals` on the audience and on one exact subject, `repo:BuzzL@<owner id>/workforce-pipeline@<repository id>:environment:workforce`. Only a workflow of that repository running in its `workforce` GitHub Environment (approval-gated, defined in `workforce-github`) can assume it. No ExternalId exists for web identity; the subject carries the immutable IDs.

| Statement | Actions | Resource | Why |
|---|---|---|---|
| `CreateChangeSets` | `cloudformation:CreateChangeSet` | stacks `wrkf-foundation-pipeline-*-stack` | the only way a change is made; `cloudformation:RoleArn` must be the execution role and `cloudformation:TemplateUrl` the asset bucket (both URL forms) |
| `FollowChangeSets` | `ExecuteChangeSet`, `DeleteChangeSet`, `DescribeChangeSet`, `DescribeStacks`, `DescribeStackEvents`, `GetTemplate` | the same stacks | run the change set, follow it, and diff against the deployed template |
| `TagStacks` | `cloudformation:TagResource`, `UntagResource` | the same stacks | stack tags, only the keys of `docs/TAG_CONVENTION.md` (`aws:TagKeys`) |
| `ReadToolkitStack` | `cloudformation:DescribeStacks` | `wrkf-foundation-cdktoolkit-stack` | the CLI looks the bootstrap stack up on some paths |
| `PassExecutionRole` | `iam:PassRole` | the execution role only | `iam:PassedToService` = `cloudformation.amazonaws.com` |
| `CheckAssetBucket` | `s3:GetBucketLocation`, `GetEncryptionConfiguration`, `ListBucket` | the asset bucket | the CLI checks the bucket's owner and encryption and whether an asset is already there |
| `PublishAssets` | `s3:PutObject`, `GetObject` | objects of the asset bucket | upload the assets and the template; CloudFormation reads the template with the caller's credentials |

Not allowed: `CreateStack`, `UpdateStack`, `DeleteStack` (a change set creates a new stack; deleting a stack, or recovering one in `ROLLBACK_COMPLETE`, is the maintainer's), any other role to pass, and anything that creates resources directly.

### Execution role

Trust: the service `cloudformation.amazonaws.com`, `aws:SourceAccount` the account itself and `aws:SourceArn` like `stack/wrkf-foundation-pipeline-*-stack/*` (confused deputy), as for the execution roles of the environment accounts. No boundary of its own: its policy is the permission set.

| Statement | Actions | Resource | Why |
|---|---|---|---|
| `CreateBoundedRoles` | `iam:CreateRole`, `PutRolePolicy` | `role/apps/pipeline/wrkf-foundation-pipeline-*-role` | the roles of the stacks (functions, tasks), only with `iam:PermissionsBoundary` equal to the boundary's full ARN |
| `MaintainAppRoles` | `iam:GetRole`, `GetRolePolicy`, `ListRolePolicies`, `ListAttachedRolePolicies`, `DeleteRolePolicy`, `DeleteRole` | the same roles | what CloudFormation reads before it updates a role, and removes on delete |
| `TagAppRoles` | `iam:TagRole`, `UntagRole` | the same roles | stack tags propagate to the roles, only the keys of the convention |

The path `/apps/pipeline/` keeps every `/platform/` role (the deploy role, the execution role itself, the agent role) and the boundary out of reach. Not allowed: `AttachRolePolicy` (no managed policy, so no `AdministratorAccess` to attach; the CDK app gives its roles inline policies), `PutRolePermissionsBoundary`, `DeleteRolePermissionsBoundary`, `UpdateAssumeRolePolicy`, and any role without the boundary.

It starts with nothing else. Each service a stack needs (SQS, Lambda with `iam:PassRole` to `lambda.amazonaws.com`, API Gateway, ECS, alarms) is added to this role, with its reason and a literal test, in its own PR before the `workforce-pipeline` change that needs it (the CI-permissions-first rule of `CLAUDE.md`). An empty CDK stack needs none.

### Permissions boundary

It lists what a role of the pipeline may ever do: `logs:CreateLogStream` and `logs:PutLogEvents` on the log groups `/aws/lambda/wrkf-foundation-pipeline-*-function`. Nothing else until a workload needs it, and each addition is a change of this policy with the maintainer's approval. It has no Deny: a boundary is an allow list, and whatever it does not name is denied to the bounded role.

**The boundary needs the maintainer's explicit approval before it is applied** (`CLAUDE.md`): a boundary can lock a role out.

## The custom bootstrap template

`bootstrap/accounts/workforce/cdk-bootstrap.yaml` replaces the default `cdk bootstrap` template. It creates the asset staging bucket `cdk-wrkf-assets-<account>-<region>` and its policy, and nothing else: no `cdk-*` roles, no ECR repository, no SSM parameter (`CliCredentialsStackSynthesizer` reads none of them).

- The bucket: SSE-S3 (no customer-managed key, as for the audit log bucket; trivy's CMK finding is ignored inline with that reason), all public access blocked, `BucketOwnerEnforced`, versioned with old versions expired after 30 days, `DeletionPolicy: Retain`, the tags of `docs/TAG_CONVENTION.md`.
- The policy: one Deny, `s3:*` for any principal when `aws:SecureTransport` is `false`. Its wildcards are narrowed by the condition and the two bucket resources, and the test asserts it literally, as for the state bucket.
- The parameters the CDK CLI sends (`Qualifier`, `FileAssetsBucketKmsKeyId`, `PublicAccessBlockConfiguration`) accept one value each. The CLI does not send `CloudFormationExecutionPolicies` unless asked, and the template does not declare it. Its warning about a default `AdministratorAccess` execution policy is about the default template and does not apply: nothing here reads that value.
- The outputs the CLI reads: `BucketName`, `BucketDomainName`, `BootstrapVersion` (`1`, this template's own version line). `BootstrapVariant` stops the CLI from overwriting it with the default template.
- Long-form intrinsics only (`Fn::Sub`, not `!Sub`), so that Terraform can `yamldecode()` the file. The stack takes its qualifier from the template, so the deploy role and the bucket cannot drift apart.

Bootstrapping is the maintainer's, with the SSO admin session of `workforce`. It needs no IAM permission beyond creating a bucket and its policy:

```sh
npx aws-cdk@2 bootstrap aws://<workforce account id>/<region> \
  --template bootstrap/accounts/workforce/cdk-bootstrap.yaml \
  --toolkit-stack-name wrkf-foundation-cdktoolkit-stack \
  --qualifier wrkf \
  --termination-protection \
  --profile <workforce admin profile>
```

## Tests

`bootstrap/accounts/workforce/tests/stack.tftest.hcl`, mocked provider: the trust and the permission set of both roles and the boundary, literally; the plan role's read of exactly these three; nothing exists while `pipeline` is unset; the bootstrap template (only the bucket and its policy, the parameters, the bucket's protection, the TLS-only Deny literally, the outputs the CLI reads); and, over every policy of the pipeline, no `*` principal, no action containing `*`, no `NotAction`, `NotResource`, `NotPrincipal` or `Principal` in a statement, no bare `*` resource, and no Deny.

## Why a local apply

The roles and the boundary are IAM resources and the CI apply role has no IAM write (`docs/ACCOUNT_CI_BASELINES.md`, decision 2), so they are part of the baseline stack, applied locally with the maintainer's session, like the agent and deploy roles. CI plans the stack through the plan role, which reads these three (`extra_read_statements`).

## Applying

1. Approve the boundary in review.
2. Once `workforce-pipeline` exists, set `pipeline` in the gitignored `terraform.tfvars` of `bootstrap/accounts/workforce` (`terraform.tfvars.example`), then `terraform plan` (two roles, one policy, the plan role's read of them) and `terraform apply`, from the pull request branch before merging, so the drift job after the merge stays green.
3. Set the GitHub Environment secret of `workforce` in `workforce-pipeline` from the outputs `pipeline_deploy_role_arn` and `pipeline_exec_role_arn` (sensitive, never printed in CI).

CI plans this stack with `pipeline = null`, as with `deploy` in the environment accounts (`docs/DEPLOY_ROLES.md`): after the local apply the CI plan shows the three as destroys until CI receives the same value. The value is public, so the follow-up commits it as a local or passes it as `TF_VAR_pipeline`, in its own change.

## Preconditions for the CDK app

- Synthesizer: `CliCredentialsStackSynthesizer` with the qualifier `wrkf`; the CLI then deploys with the deploy role's own credentials and assumes no `cdk-*` role. Deploy with `cdk deploy --role-arn <execution role ARN>` and `--toolkit-stack-name wrkf-foundation-cdktoolkit-stack`.
- Stack names `wrkf-foundation-pipeline-<qualifier>-stack`; every role with an explicit name `wrkf-foundation-pipeline-<name>-role`, the path `/apps/pipeline/` and the boundary (`PermissionsBoundary.of(app)`), inline policies only.
- The stack tags of `docs/TAG_CONVENTION.md` on every deploy.
- Open item, proved on the first deploy: CloudFormation sets `aws:SourceArn` when it assumes the execution role (the same open point as for the environment accounts).
