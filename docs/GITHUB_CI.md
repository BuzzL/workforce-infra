# CI roles for workforce-github

## Context

`workforce-github` manages GitHub as code (repos, rulesets, GitHub Environments) with the GitHub provider. The provider is not AWS, so its CI needs AWS for two things only: the Terraform state of its stack `live/github` in the state bucket, and the key of the GitHub App the provider authenticates as. This repo owns the AWS side of that; `workforce-github` owns the GitHub side (see the Scope section of `CLAUDE.md`).

## Decisions

### 1. Two roles in the management account, defined in `bootstrap/github_ci.tf`

| Role | Trusted environment (of `workforce-github`) | Can do |
|---|---|---|
| `github-infra-github` | `github` | read and write the state and lockfile of `live/github`, read the write App's key |
| `github-infra-github-plan` | `github-plan` | read the state object of `live/github`, read the read-only App's key |

Both trust the OIDC provider of the account for one exact subject (`repo:<owner>@<id>/workforce-github@<id>:environment:<environment>`, `StringEquals` on `sub` and `aud`). The `github-plan` environment has no reviewer and accepts any branch, so its role is read-only and only ever sees the read-only App. No other AWS permission: nothing in AWS is managed through them.

Same account as the state bucket, so no bucket policy change: the identity policies are enough.

### 2. The App keys are parameters created by hand

`/workforce/github/app-write-key` and `/workforce/github/app-read-key`, SecureString with the AWS managed key of SSM (no customer key, no monthly cost). They are created by the maintainer, never by Terraform: a key in a resource would end up in the state. Decrypting needs `kms:Decrypt`; the key ID is not known to Terraform, so the policy names every key of the account in the region and narrows it to calls from SSM for exactly that parameter (`kms:ViaService` and the parameter's ARN in the encryption context). This is the one wildcard, asserted literally in `bootstrap/tests/bootstrap.tftest.hcl`.

Rejected: Secrets Manager (a monthly fee per secret for the same effect), a customer-managed KMS key (monthly fee, key policy to maintain), SOPS in `workforce-github` (the secret values would still reach the Terraform state).

## Create the parameters (maintainer, once)

```sh
# After creating the two GitHub Apps (see workforce-github docs) and downloading their keys:
aws ssm put-parameter --name /workforce/github/app-write-key --type SecureString --value file://write-app.private-key.pem
aws ssm put-parameter --name /workforce/github/app-read-key  --type SecureString --value file://read-app.private-key.pem
shred -u write-app.private-key.pem read-app.private-key.pem   # or rm -P on macOS
```

Then apply `bootstrap/` locally (the roles) and use `github_ci_role_arns` for the secrets of the `github` and `github-plan` environments of `workforce-github`.
