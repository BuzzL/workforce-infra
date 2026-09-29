# workforce-infra

Terraform monorepo for the AWS side of the AI Workforce: Organization, the workforce account and the `development` / `production` environment accounts. Cross-repo context lives in the workspace `CLAUDE.md` one level up, when it's present.

## Rules

- **Commit rule**: every commit is short (one logical change), testable (`terraform validate`, `terraform test` with mocked providers, tflint, trivy) and not breakable (CI green on its own). Conventional Commits.
- Changes land on `main` only through a squash-merged PR with green CI.
- Least privilege: cross-account trust always carries conditions (source account, ExternalId, principal ARN). Never use a `*` principal or `*:*` action.
- Public repo: never commit account IDs, account emails, ARNs, state, `*.tfvars` or `backend.hcl`. Commit `*.example` files instead.

## Layout

- `bootstrap/`: state bucket, OIDC provider and management CI role. The only stack applied locally.
- `live/`: per-account and per-environment root stacks. `modules/`: reusable modules.
- `docs/BOOTSTRAP.md`: manual bootstrap of the management account, SSO and the Terraform tooling.
- `Makefile`, `scripts/`: `make check` runs fmt, validate, tflint, version and Dependabot conventions, trivy, `terraform test` and `make selftest` (the gates' own test). CI runs the same targets. Loops live in `scripts/each.sh`, not in recipes (macOS Make 3.81). Terraform version: `.terraform-version`.
- Each stack or module declares `required_version >= 1.9` and pins AWS to `~> 6`; `make versions` enforces the values, tflint that constraints exist. A stack that declares providers must be in the terraform block of `.github/dependabot.yml` (`make dependabot`).

_Stacks and modules are added commit by commit; the tree is empty for now._
