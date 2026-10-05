# Cross-account role module

`modules/cross-account-role` creates every role of the environment model (`docs/ENVIRONMENT_PERMISSIONS.md`) so that least privilege is enforced in one place. It implements the decision and does not change it. The agent roles use it through `modules/agent-role` (`docs/AGENT_ROLES.md`).

## What it creates

One IAM role under `/platform/`, its trust policy, one inline policy named `permissions` (omitted when there are no statements) and the exclusive resources that make Terraform the only owner of the role's policies: anything attached outside the module is removed on the next apply.

## Inputs

| Input | Meaning |
|---|---|
| `name` | a platform role name, validated against the naming regexp: `<acct>-<project>-(agent-role\|infra-role\|infra-plan-role\|github-role\|github-plan-role\|<app>-deploy-role\|<app>-exec-role)`, the account being a key of `scripts/environment-keys.tsv`. A name from the application regexp is refused: those roles are created by the application's own stack |
| `path` | default `/platform/` |
| `description`, `max_session_duration`, `tags` | as in IAM (session 3600 to 43200 seconds) |
| `permissions_boundary_arn` | optional. The module only attaches a boundary: creating one can lock a role out and needs the maintainer's approval |
| `trust` | who may assume the role: exactly one block, chosen by `mode` |
| `statements` | the permission set: `sid`, `effect` (default `Allow`), `actions`, `resources`, optional `conditions`, optional `any_resource_reason` |

### Trust modes

| Mode | Principal | Always required |
|---|---|---|
| `assume_role` | one role by exact ARN | `aws:PrincipalAccount` (the source account, which must match the ARN), `aws:PrincipalArn` (the same ARN), `sts:ExternalId` (one value, two during a rotation). Optional `sts:RoleSessionName` as a fixed prefix and one trailing `*` (`agent-*`) |
| `web_identity` | an OIDC provider | `StringEquals` on the audience and on one exact subject. No ExternalId: it does not exist for web identity |
| `service` | one AWS service (`<name>.amazonaws.com`) | `aws:SourceAccount` and `aws:SourceArn` of that account, whose resource part cannot start with a wildcard |

Refused at plan time: a wildcard in a principal, the account root, a principal outside the declared source account, no ExternalId, an ExternalId with wildcard characters, a session pattern that is not `prefix-*`, a wildcard or policy variable (`$`) in a subject or audience, a service source ARN that is not of the source account, two trust blocks.

### Permission statements

The type has no `NotAction`, `NotPrincipal` or `NotResource`, so they cannot be written. Also refused:

- an Allow with any wildcard action (`*`, `service:*`, `service:Get*`);
- in an Allow, a resource that is not an ARN with a fixed service and account (`arn:aws:<service>:<region>:<account>:<resource>`) whose resource part does not start with a wildcard, so `arn:aws:s3:::*` and `arn:aws:iam::*:role/*` are refused. Inside the resource part patterns such as `name-*-function` are allowed and are the reviewer's to check;
- resource `*` in an Allow, unless `any_resource_reason` (not blank) says why. This is the exception of `docs/ENVIRONMENT_PERMISSIONS.md` that the maintainer approves in review;
- a Deny with a wildcard action and no condition, and a Deny whose resource is `*` and which has no condition;
- a condition without a key or a value (it would narrow nothing), and two statements with the same `sid`.

## Tests

`modules/cross-account-role/tests` runs with a mocked provider (`terraform test`, part of `make check` and CI). `trust.tftest.hcl` asserts the three trust documents literally and every refusal above. `permissions.tftest.hcl` asserts the rendered permission set literally, that no document contains `NotAction`, `NotPrincipal`, `NotResource` or a `*` principal or action, that a narrowed Deny is rendered with its condition, and that the module owns the role's policies exclusively.

## Using it

```hcl
module "agent" {
  source = "../../modules/cross-account-role"

  name        = "test-foundation-agent-role"
  description = "Read only access for the developer agent."

  trust = {
    mode = "assume_role"
    assume_role = {
      principal_arn        = var.agent_task_role_arn
      source_account_id    = var.workforce_account_id
      external_ids         = [var.external_id]
      session_name_pattern = "agent-*"
    }
  }

  statements = [{
    sid       = "ReadFunctions"
    actions   = ["lambda:GetFunctionConfiguration"]
    resources = ["<function ARN pattern>"]
  }]
}
```

The values of `trust` come from variables, never from the repository (`CLAUDE.md`).

## Limits worth knowing

- AWS stores a role principal as its unique ID: if the principal role is deleted and recreated, the trust stops matching until the next apply. This fails closed.
- `permissions_boundary_arn` and the OIDC provider's account are not validated beyond their type; the stack that uses the module passes them, and the reviewer checks them.
- An ExternalId is a 16 to 1000 character string, not a measured secret: generate it with enough entropy (`docs/ENVIRONMENT_PERMISSIONS.md`).
