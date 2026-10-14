mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
  }
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
}

run "wires_the_baseline" {
  command = apply

  # Its own key is the one CI derives from the stack path. The key of the stack that CI
  # applies is a different one: the apply role reaches that one and never this one.
  assert {
    condition     = local.state_key == "bootstrap/accounts/workforce/terraform.tfstate"
    error_message = "The state key must match the backend key CI derives from the stack path."
  }

  assert {
    condition     = local.live_state_key == "live/accounts/workforce/terraform.tfstate"
    error_message = "The apply role must reach the state of live/accounts/workforce."
  }

  assert {
    condition     = module.baseline.apply_role_arn != module.baseline.plan_role_arn
    error_message = "The apply and plan roles must be different roles."
  }
}

run "bootstrap_account_id_must_be_12_digits" {
  command = plan

  variables {
    break_glass_account_id = "not-an-id"
  }

  expect_failures = [var.break_glass_account_id]
}

# The agent roles of the environment accounts trust this role (docs/AGENT_ROLES.md).
run "agent_task_role_is_assumed_by_ecs_tasks_of_this_account_only" {
  command = apply

  assert {
    condition     = module.agent_role.name == "wrkf-foundation-agent-role"
    error_message = "The agent task role must be wrkf-foundation-agent-role."
  }

  assert {
    condition = jsondecode(module.agent_role.trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = "111122223333" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:ecs:eu-west-1:111122223333:task/*" }
        }
      }]
    }
    error_message = "Only ECS tasks of the workforce account may assume the agent task role."
  }

  # No permissions yet: each one arrives with the change that needs it.
  assert {
    condition     = module.agent_role.permissions_policy == null
    error_message = "The agent task role starts with no permissions."
  }

  assert {
    condition = jsonencode(local.agent_read_statements) == jsonencode([{
      Sid      = "ReadAgentTaskRole"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = ["arn:aws:iam::111122223333:role/platform/wrkf-foundation-agent-role"]
    }])
    error_message = "The plan role may read exactly the agent task role and only through read actions."
  }

  # The statement really reaches the plan role: the stack passes it on to the baseline.
  assert {
    condition     = contains([for s in jsondecode(module.baseline.plan_read_policy).Statement : s.Sid], "ReadAgentTaskRole")
    error_message = "The plan role must be able to read the agent role."
  }
}

# The matrix runner roles: one per environment, one exact OIDC subject each, and the
# agent role of that environment is the only thing each may assume.
run "no_matrix_roles_while_the_variable_is_unset" {
  command = apply

  assert {
    condition     = length(module.matrix_role) == 0
    error_message = "Without var.matrix no matrix runner role exists."
  }
}

run "matrix_roles_trust_one_environment_each_and_assume_one_agent_role" {
  command = apply

  variables {
    matrix = {
      environment_account_ids = { test = "222233334444", quality = "333344445555", demo = "444455556666" }
    }
  }

  assert {
    condition     = [for env in ["test", "quality", "demo"] : module.matrix_role[env].name] == ["wrkf-foundation-matrix-test-role", "wrkf-foundation-matrix-quality-role", "wrkf-foundation-matrix-demo-role"]
    error_message = "The runner roles must be wrkf-foundation-matrix-<environment>-role."
  }

  assert {
    condition = jsondecode(module.matrix_role["quality"].trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-infra@1394667495:environment:quality-matrix"
          }
        }
      }]
    }
    error_message = "The quality runner role must be trusted for workforce-infra in the quality-matrix environment only."
  }

  assert {
    condition = jsondecode(module.matrix_role["demo"].permissions_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid      = "AssumeTheAgentRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = ["arn:aws:iam::444455556666:role/platform/demo-foundation-agent-role"]
      }]
    }
    error_message = "The demo runner role may assume the agent role of the demo account and nothing else."
  }
}

run "matrix_needs_the_three_environments" {
  command         = plan
  expect_failures = [var.matrix]

  variables {
    matrix = {
      environment_account_ids = { test = "222233334444", quality = "333344445555" }
    }
  }
}

# The CDK deployment of workforce-pipeline (docs/CDK_BOOTSTRAP.md).
run "no_pipeline_roles_while_the_variable_is_unset" {
  command = apply

  assert {
    condition     = length(module.pipeline_deploy_role) == 0 && length(module.pipeline_exec_role) == 0 && length(aws_iam_policy.pipeline_boundary) == 0
    error_message = "Without var.pipeline neither pipeline role nor the boundary exists."
  }

  assert {
    condition     = length(local.pipeline_read_statements) == 0
    error_message = "Without var.pipeline the plan role reads nothing of the pipeline."
  }
}

run "pipeline_repository_id_must_be_numeric" {
  command         = plan
  expect_failures = [var.pipeline]

  variables {
    pipeline = { github_repository_id = "workforce-pipeline" }
  }
}

run "pipeline_deploy_role_is_trusted_by_one_subject_and_only_starts_change_sets" {
  command = apply

  variables {
    pipeline = { github_repository_id = "987654321" }
  }

  assert {
    condition     = module.pipeline_deploy_role[0].name == "wrkf-foundation-pipeline-deploy-role"
    error_message = "The deploy role must be wrkf-foundation-pipeline-deploy-role."
  }

  assert {
    condition = jsondecode(module.pipeline_deploy_role[0].trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-pipeline@987654321:environment:workforce"
          }
        }
      }]
    }
    error_message = "Only workforce-pipeline in its workforce GitHub Environment may assume the deploy role."
  }

  assert {
    condition = jsondecode(module.pipeline_deploy_role[0].permissions_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "CreateChangeSets"
          Effect   = "Allow"
          Action   = ["cloudformation:CreateChangeSet"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/wrkf-foundation-pipeline-*-stack/*"]
          Condition = {
            StringEquals = { "cloudformation:RoleArn" = ["arn:aws:iam::111122223333:role/platform/wrkf-foundation-pipeline-exec-role"] }
            StringLike = { "cloudformation:TemplateUrl" = [
              "https://s3.eu-west-1.amazonaws.com/cdk-wrkf-assets-111122223333-eu-west-1/*",
              "https://cdk-wrkf-assets-111122223333-eu-west-1.s3.eu-west-1.amazonaws.com/*",
            ] }
          }
        },
        {
          Sid    = "FollowChangeSets"
          Effect = "Allow"
          Action = [
            "cloudformation:ExecuteChangeSet", "cloudformation:DeleteChangeSet", "cloudformation:DescribeChangeSet",
            "cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents", "cloudformation:GetTemplate",
          ]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/wrkf-foundation-pipeline-*-stack/*"]
        },
        {
          Sid       = "TagStacks"
          Effect    = "Allow"
          Action    = ["cloudformation:TagResource", "cloudformation:UntagResource"]
          Resource  = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/wrkf-foundation-pipeline-*-stack/*"]
          Condition = { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["App", "Archetype", "Environment", "ManagedBy", "Project", "Repository", "Stack", "Target"] } }
        },
        {
          Sid      = "ReadToolkitStack"
          Effect   = "Allow"
          Action   = ["cloudformation:DescribeStacks"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/wrkf-foundation-cdktoolkit-stack/*"]
        },
        {
          Sid       = "PassExecutionRole"
          Effect    = "Allow"
          Action    = ["iam:PassRole"]
          Resource  = ["arn:aws:iam::111122223333:role/platform/wrkf-foundation-pipeline-exec-role"]
          Condition = { StringEquals = { "iam:PassedToService" = ["cloudformation.amazonaws.com"] } }
        },
        {
          Sid      = "CheckAssetBucket"
          Effect   = "Allow"
          Action   = ["s3:GetBucketLocation", "s3:GetEncryptionConfiguration", "s3:ListBucket"]
          Resource = ["arn:aws:s3:::cdk-wrkf-assets-111122223333-eu-west-1"]
        },
        {
          Sid      = "PublishAssets"
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:GetObject"]
          Resource = ["arn:aws:s3:::cdk-wrkf-assets-111122223333-eu-west-1/*"]
        },
      ]
    }
    error_message = "The deploy role may only publish assets, run change sets of the pipeline's stacks with its execution role, and read the toolkit stack."
  }
}

run "pipeline_exec_role_is_cloudformation_only_and_creates_bounded_roles" {
  command = apply

  variables {
    pipeline = { github_repository_id = "987654321" }
  }

  assert {
    condition     = module.pipeline_exec_role[0].name == "wrkf-foundation-pipeline-exec-role"
    error_message = "The execution role must be wrkf-foundation-pipeline-exec-role."
  }

  assert {
    condition = jsondecode(module.pipeline_exec_role[0].trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "cloudformation.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = "111122223333" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:cloudformation:eu-west-1:111122223333:stack/wrkf-foundation-pipeline-*-stack/*" }
        }
      }]
    }
    error_message = "Only CloudFormation, acting for the pipeline's stacks in this account, may assume the execution role."
  }

  assert {
    condition = jsondecode(module.pipeline_exec_role[0].permissions_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "CreateBoundedRoles"
          Effect    = "Allow"
          Action    = ["iam:CreateRole", "iam:PutRolePolicy"]
          Resource  = ["arn:aws:iam::111122223333:role/apps/pipeline/wrkf-foundation-pipeline-*-role"]
          Condition = { StringEquals = { "iam:PermissionsBoundary" = ["arn:aws:iam::111122223333:policy/platform/wrkf-foundation-pipeline-boundary"] } }
        },
        {
          Sid    = "MaintainAppRoles"
          Effect = "Allow"
          Action = [
            "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
            "iam:DeleteRolePolicy", "iam:DeleteRole",
          ]
          Resource = ["arn:aws:iam::111122223333:role/apps/pipeline/wrkf-foundation-pipeline-*-role"]
        },
        {
          Sid       = "TagAppRoles"
          Effect    = "Allow"
          Action    = ["iam:TagRole", "iam:UntagRole"]
          Resource  = ["arn:aws:iam::111122223333:role/apps/pipeline/wrkf-foundation-pipeline-*-role"]
          Condition = { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["App", "Archetype", "Environment", "ManagedBy", "Project", "Repository", "Stack", "Target"] } }
        },
      ]
    }
    error_message = "The execution role may create roles only under /apps/pipeline/ with the boundary, and nothing else yet."
  }

  # The boundary is the full ARN of this one policy, under /platform/ where the execution role cannot reach.
  assert {
    condition     = local.pipeline_boundary_arn == "arn:aws:iam::111122223333:policy/platform/wrkf-foundation-pipeline-boundary"
    error_message = "The execution role must require the pipeline's own boundary by its full ARN."
  }
}

run "pipeline_boundary_allows_only_own_function_log_writes" {
  command = apply

  variables {
    pipeline = { github_repository_id = "987654321" }
  }

  assert {
    condition     = aws_iam_policy.pipeline_boundary[0].name == "wrkf-foundation-pipeline-boundary" && aws_iam_policy.pipeline_boundary[0].path == "/platform/"
    error_message = "The boundary must be /platform/wrkf-foundation-pipeline-boundary."
  }

  assert {
    condition = jsondecode(aws_iam_policy.pipeline_boundary[0].policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid      = "WriteOwnFunctionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:eu-west-1:111122223333:log-group:/aws/lambda/wrkf-foundation-pipeline-*-function:*"]
      }]
    }
    error_message = "The boundary allows writing the pipeline's own function logs and nothing else."
  }
}

run "pipeline_plan_role_reads_the_two_roles_and_the_boundary" {
  command = apply

  variables {
    pipeline = { github_repository_id = "987654321" }
  }

  assert {
    condition = jsonencode(local.pipeline_read_statements) == jsonencode([
      {
        Sid      = "ReadPipelineRoles"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
        Resource = ["arn:aws:iam::111122223333:role/platform/wrkf-foundation-pipeline-deploy-role", "arn:aws:iam::111122223333:role/platform/wrkf-foundation-pipeline-exec-role"]
      },
      {
        Sid      = "ReadPipelineBoundary"
        Effect   = "Allow"
        Action   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListPolicyTags"]
        Resource = ["arn:aws:iam::111122223333:policy/platform/wrkf-foundation-pipeline-boundary"]
      },
    ])
    error_message = "The plan role may read exactly the pipeline roles and boundary, through read actions only."
  }

  assert {
    condition     = length(setintersection(["ReadPipelineRoles", "ReadPipelineBoundary"], [for s in jsondecode(module.baseline.plan_read_policy).Statement : s.Sid])) == 2
    error_message = "The plan role must be able to read the pipeline roles and the boundary."
  }
}

# The ticket's invariants, over every policy of the pipeline: no "*" principal, no wildcard
# action and no Not* element in an Allow, and no Deny at all.
run "pipeline_policies_have_no_wildcard_principal_action_or_not_element" {
  command = apply

  variables {
    pipeline = { github_repository_id = "987654321" }
  }

  assert {
    condition = alltrue(flatten([
      for doc in [module.pipeline_deploy_role[0].trust_policy, module.pipeline_exec_role[0].trust_policy] : [
        for s in jsondecode(doc).Statement : [
          for p in flatten([for v in values(s.Principal) : v]) : p != "*"
        ]
      ]
    ]))
    error_message = "No trust policy of the pipeline may name a \"*\" principal."
  }

  assert {
    condition = alltrue(flatten([
      for doc in [module.pipeline_deploy_role[0].permissions_policy, module.pipeline_exec_role[0].permissions_policy, aws_iam_policy.pipeline_boundary[0].policy] : [
        for s in jsondecode(doc).Statement : [
          s.Effect == "Allow",
          length(setintersection(keys(s), ["NotAction", "NotResource", "NotPrincipal", "Principal"])) == 0,
          alltrue([for a in flatten([s.Action]) : !strcontains(a, "*")]),
          alltrue([for r in flatten([s.Resource]) : r != "*"]),
        ]
      ]
    ]))
    error_message = "Every statement of the pipeline is an Allow with named actions and resources, and no Not* element."
  }
}

# The custom CDK bootstrap template (cdk-bootstrap.yaml): the staging bucket and nothing else.
run "cdk_bootstrap_template_holds_only_the_staging_bucket" {
  command = plan

  assert {
    condition = { for k, r in local.cdk_bootstrap_template.Resources : k => r.Type } == {
      StagingBucket       = "AWS::S3::Bucket"
      StagingBucketPolicy = "AWS::S3::BucketPolicy"
    }
    error_message = "The bootstrap template creates the staging bucket and its policy, and no role or other resource."
  }

  assert {
    condition = { for k, p in local.cdk_bootstrap_template.Parameters : k => p.AllowedValues if k != "BootstrapVariant" } == {
      Qualifier                      = ["wrkf"]
      FileAssetsBucketKmsKeyId       = ["AWS_MANAGED_KEY"]
      PublicAccessBlockConfiguration = ["true"]
    }
    error_message = "The parameters the CDK CLI sends accept one value each: the qualifier wrkf, the managed key marker and a blocked public access."
  }

  assert {
    condition     = local.cdk_qualifier == "wrkf" && local.cdk_bootstrap_template.Resources.StagingBucket.Properties.BucketName == { "Fn::Sub" = "cdk-$${Qualifier}-assets-$${AWS::AccountId}-$${AWS::Region}" }
    error_message = "The bucket must be cdk-wrkf-assets-<account>-<region>, the one the deploy role names."
  }

  assert {
    condition = local.cdk_bootstrap_template.Resources.StagingBucket.Properties.PublicAccessBlockConfiguration == {
      BlockPublicAcls = true, BlockPublicPolicy = true, IgnorePublicAcls = true, RestrictPublicBuckets = true
    }
    error_message = "The staging bucket must block every form of public access."
  }

  assert {
    condition = (
      local.cdk_bootstrap_template.Resources.StagingBucket.Properties.BucketEncryption.ServerSideEncryptionConfiguration[0].ServerSideEncryptionByDefault.SSEAlgorithm == "AES256" &&
      local.cdk_bootstrap_template.Resources.StagingBucket.Properties.OwnershipControls.Rules[0].ObjectOwnership == "BucketOwnerEnforced" &&
      local.cdk_bootstrap_template.Resources.StagingBucket.Properties.VersioningConfiguration.Status == "Enabled" &&
      local.cdk_bootstrap_template.Resources.StagingBucket.DeletionPolicy == "Retain"
    )
    error_message = "The staging bucket is encrypted, owner-enforced, versioned and retained."
  }

  assert {
    condition     = contains(local.cdk_bootstrap_template.Resources.StagingBucket.Properties.Tags, { Key = "Stack", Value = local.cdk_toolkit_stack })
    error_message = "The bucket's Stack tag must name the toolkit stack the deploy role reads."
  }

  # The one statement: a Deny whose "*" principal and s3:* are narrowed by the TLS condition.
  assert {
    condition = local.cdk_bootstrap_template.Resources.StagingBucketPolicy.Properties.PolicyDocument == {
      Version = "2012-10-17"
      Statement = [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource  = [{ "Fn::GetAtt" = ["StagingBucket", "Arn"] }, { "Fn::Sub" = "$${StagingBucket.Arn}/*" }]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }]
    }
    error_message = "The bucket policy is exactly the TLS-only Deny: no Allow, and its wildcards narrowed by aws:SecureTransport."
  }

  assert {
    condition     = local.cdk_bootstrap_template.Outputs.BootstrapVersion.Value == "1" && local.cdk_bootstrap_template.Outputs.BucketName.Value == { Ref = "StagingBucket" }
    error_message = "The CDK CLI reads BootstrapVersion and BucketName from the toolkit stack's outputs."
  }
}
