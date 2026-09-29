# workforce-infra

Terraform monorepo for the AWS side of the AI Workforce: Organization, the workforce account and the `development` / `production` environment accounts. Cross-repo context lives in the workspace `CLAUDE.md` one level up, when it's present.

## Rules

- **Commit rule**: every commit is short (one logical change), testable (`terraform validate`, `terraform test` with mocked providers, tflint, trivy) and not breakable (CI green on its own). Conventional Commits.
- Changes land on `main` only through a squash-merged PR with green CI.
- Least privilege: cross-account trust always carries conditions (source account, ExternalId, principal ARN). Never use a `*` principal or `*:*` action.
- Public repo: never commit account IDs, account emails, ARNs, state, `*.tfvars` or `backend.hcl`. Commit `*.example` files instead.

## Layout

_Skeleton in progress: modules and stacks are added commit by commit._
