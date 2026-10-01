mock_provider "aws" {}

variables {
  allowed_region = "eu-south-1"
}

# Values below are asserted literally on purpose: a change to any policy must be a
# visible, reviewed change to this file.

run "leave_organization_is_denied" {
  command = plan

  assert {
    condition = jsondecode(aws_organizations_policy.this["deny-leave-organization"].content) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "DenyLeaveOrganization"
          Effect   = "Deny"
          Action   = ["organizations:LeaveOrganization"]
          Resource = "*"
        }
      ]
    }
    error_message = "The policy must be exactly one Deny of organizations:LeaveOrganization."
  }
}

run "root_user_is_denied_everything" {
  command = plan

  assert {
    condition = jsondecode(aws_organizations_policy.this["deny-root-user"].content) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyRootUser"
          Effect    = "Deny"
          Action    = "*"
          Resource  = "*"
          Condition = { StringLike = { "aws:PrincipalArn" = "arn:aws:iam::*:root" } }
        }
      ]
    }
    error_message = "The policy must be exactly one Deny of * that applies only to a root principal."
  }
}

run "cloudtrail_cannot_be_disabled" {
  command = plan

  assert {
    condition = jsondecode(aws_organizations_policy.this["deny-disable-cloudtrail"].content) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "DenyDisableCloudTrail"
          Effect = "Deny"
          Action = [
            "cloudtrail:DeleteEventDataStore",
            "cloudtrail:DeleteTrail",
            "cloudtrail:PutEventSelectors",
            "cloudtrail:StopEventDataStoreIngestion",
            "cloudtrail:StopLogging",
            "cloudtrail:UpdateEventDataStore",
            "cloudtrail:UpdateTrail",
          ]
          Resource = "*"
        }
      ]
    }
    error_message = "The policy must be exactly one Deny of the listed CloudTrail actions."
  }
}

run "every_policy_is_an_scp_with_only_deny_statements" {
  command = plan

  assert {
    condition     = alltrue([for p in aws_organizations_policy.this : p.type == "SERVICE_CONTROL_POLICY"])
    error_message = "Every policy must be a SERVICE_CONTROL_POLICY."
  }

  assert {
    condition = alltrue([
      for p in aws_organizations_policy.this :
      alltrue([for s in jsondecode(p.content).Statement : s.Effect == "Deny"])
    ])
    error_message = "Every statement of every SCP must be a Deny: wildcards are only allowed there."
  }
}

run "module_creates_these_policies_and_attaches_none" {
  command = apply

  assert {
    condition     = length(output.policy_ids) == 4
    error_message = "The module must create exactly the four baseline policies."
  }

  # The module is a library of definitions: attaching is the job of the stack that calls
  # it, in stages. This scans every Terraform file under the module (*.tf and *.tf.json,
  # nested directories included, tests and .terraform excluded) for an attachment
  # resource. It is a text guard: it cannot see through a module call, so a module block
  # is rejected as well.
  assert {
    condition = length([
      for f in fileset(path.module, "**") : f
      if can(regex("\\.tf(\\.json)?$", f)) && !can(regex("^(tests|\\.terraform)/", f))
      && strcontains(file("${path.module}/${f}"), "aws_organizations_policy_attachment")
    ]) == 0
    error_message = "The module must not attach any SCP."
  }

  assert {
    condition = length([
      for f in fileset(path.module, "**") : f
      if can(regex("\\.tf(\\.json)?$", f)) && !can(regex("^(tests|\\.terraform)/", f))
      && can(regex("(?m)^\\s*\"?module\"?\\s", file("${path.module}/${f}")))
    ]) == 0
    error_message = "The module must not call other modules: an attachment could hide there."
  }
}
