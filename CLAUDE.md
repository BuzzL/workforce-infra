# workforce-infra

Terraform monorepo for the AWS side of the AI Workforce: Organization, the workforce account and the `test` / `qa` / `demo` environment accounts. Cross-repo context lives in the workspace `CLAUDE.md` one level up, when it's present.

## Rules

- **Commit rule**: every commit is short (one logical change), testable (`terraform validate`, `terraform test` with mocked providers, tflint, trivy) and not breakable (CI green on its own). Conventional Commits.
- Changes land on `main` only through a squash-merged PR with green CI.
- Least privilege: cross-account trust always carries conditions (source account, ExternalId, principal ARN). Never use a `*` principal, a `*` or `service:*` action, or `NotAction`/`NotPrincipal`/`NotResource` in an Allow. A `Deny` may use wildcards only when it is narrowed by a `Condition` or specific resources and is asserted literally in a test (the TLS-only state bucket policy). An SCP, a permissions boundary, or any Deny that could lock out a principal needs the maintainer's explicit approval first.
- Public repo: never commit account IDs, account emails, ARNs, state, `*.tfvars` or `backend.hcl`. Commit `*.example` files instead.

## Layout

- `bootstrap/`: state bucket, GitHub OIDC provider and the roles `github-infra-management` (apply, `management` environment) and `github-infra-management-plan` (read only, `management-plan` environment). Applied once locally (runbook in `docs/BOOTSTRAP.md`). Requires Terraform >= 1.10 for the S3 lockfile.
- `.github/workflows/terraform.yml`: read-only plan on pull requests (`management-plan` environment, redacted PR comment) and, after a merge to `main`, one approval-gated job per stack. The repo is public: `AWS_ROLE_ARN`, `AWS_ROLE_ID` and `STATE_BUCKET` are environment secrets and Terraform output goes through `scripts/redact.sh`. `scripts/ci-stacks.sh` maps paths to environments, `scripts/check-workflow.sh` checks the workflow against an allowlist. `bootstrap/` is plan only.
- `docs/BOOTSTRAP.md`: manual bootstrap of the management account, SSO and the Terraform tooling.
- `Makefile`, `scripts/`: `make check` runs fmt, validate, tflint, version and Dependabot conventions, trivy, `terraform test` and `make selftest` (the gates' own test). CI runs the same targets. Loops live in `scripts/each.sh`, not in recipes (macOS Make 3.81). Terraform version: `.terraform-version`.
- Each stack or module declares `required_version` (>= 1.9) and pins AWS to `~> 6`; `make versions` enforces the values, tflint that constraints exist. A stack that declares providers must be in the terraform block of `.github/dependabot.yml` (`make dependabot`).

