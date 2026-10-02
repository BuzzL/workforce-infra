# Audit logging: organization trail and log archive

Every API call in every account is recorded by one organization trail and kept in a bucket the other accounts cannot reach. It also gives the SCP that denies disabling logging something to protect.

## What exists

| Piece | Where | Code |
|---|---|---|
| Log bucket: private, versioned, SSE-S3, lifecycle, TLS-only Deny, Allows only for the one trail ARN | `security` account | `modules/audit-log-bucket`, wired in `live/accounts/security/audit_logs.tf` |
| Organization trail: single region, log file validation, global service events, management events only | `management` account | `modules/organization-trail`, wired in `live/management/audit_logs.tf` |

Both stacks keep the feature **off** while `audit_log_bucket_name` is unset, so merging the code creates nothing.

## Decisions

- **Single region.** The region-deny SCP leaves one region in use (`docs/ORGANIZATION_INPUTS.md`), so a multi-region trail would only add cost. Global service events (IAM, STS) are recorded in the home region.
- **Management events only.** The first copy of management events is free; data events are billed per event and are not enabled.
- **SSE-S3, no customer-managed KMS key.** A key costs money every month and adds a key policy that can lock the logs away. Log file validation digests prove the logs were not altered. Trivy AWS-0015 (trail) and AVD-AWS-0132 (bucket) are waived in code with this reason, the same as the state bucket. Only HIGH and CRITICAL findings gate CI; lower severities such as bucket access logging and CloudWatch integration of the trail are not evaluated.
- **Deleting logs is denied to everyone but the break-glass role.** The bucket policy denies `s3:DeleteObject`, `s3:DeleteObjectVersion` and `s3:DeleteBucket` unless `aws:PrincipalArn` is `OrganizationAccountAccessRole` of `security` (the maintainer approved this Deny). Lifecycle expiry is done by S3 itself and is not affected. `PutBucketPolicy` is deliberately not denied: that would lock Terraform and the account root out of the only way to repair the policy. The root user can still edit the policy, which is the recovery path.
- **CI can neither delete the trail nor stop it.** The apply role of `management` is not granted `cloudtrail:DeleteTrail` or `cloudtrail:StopLogging`, so only an admin session can. It does hold `cloudtrail:UpdateTrail`, which can still alter the trail (another bucket, validation off): that is guarded by review and by the approval of the `management` environment, not by IAM. SCPs do not apply to the management account, so IAT-36's "deny disabling logging" protects the member accounts only.
- **The bucket policy names the exact trail ARN** (`aws:SourceArn`), so no other trail, in this Organization or elsewhere, can write to it.

## Order of rollout

CI plans the `security` stack and never applies it (`docs/IDENTITY_CENTER.md`, section 5), so the bucket is created locally; the trail is created by the gated CI apply of `live/management`. The steps are ordered so that no plan runs before its permissions exist. Every step that creates a billable resource needs the maintainer's explicit yes.

1. Enable trusted access for CloudTrail in the Organization, once, from the management SSO admin session: `aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com`.
2. `bootstrap/`, locally with the management SSO admin session: set `audit_trail_enabled = true` and apply. It gives the management CI roles the CloudTrail permissions on the one trail (`bootstrap/audit_trail.tf`).
3. Set the secrets with the scripts, from the environment: `AUDIT_LOG_BUCKET=<globally unique name> scripts/set-environment-secrets.sh` for `management` and `management-plan`, and `AUDIT_LOG_BUCKET=... ORGANIZATION_ID=o-... MANAGEMENT_ACCOUNT_ID=<12 digits> scripts/set-account-environment-secrets.sh security`. They are secrets because the repository is public, and unset ones keep the feature off.
4. Right after step 3, apply `live/accounts/security` locally, as for the identity stack: set the same three values in `terraform.tfvars` (see the `.example`), review that the plan creates only the bucket and its settings and adds the bucket reads to the two CI roles, then apply. Until then the CI drift check of `security` fails by design, since it sees the bucket as missing.
5. Merge to `main`: the gated CI apply of `live/management` creates the trail. Check with `aws cloudtrail get-trail-status`, then look for a test event in the bucket.

## Known limits

- **The Deny does not stop an administrator of `security` from shortening retention.** `s3:PutLifecycleConfiguration`, `s3:PutBucketVersioning` (suspending) and overwriting objects are not denied: denying them would risk locking out Terraform or the repair path, and needs a separate maintainer decision. Only the module's validation (at least 90 days) guards retention, at apply time.
- **The trail permissions are the documented minimum, not a proven one.** AWS's guidance for organization trails also mentions `organizations:ListAccounts`, and `organizations:EnableAWSServiceAccess` when trusted access is not yet on. This setup enables trusted access by hand (step 1) and does not grant the latter. If step 5 fails with `AccessDenied` on an `organizations:` action, add only that read action to `bootstrap/audit_trail.tf` and its literal test.

## Behaviour to know

- **Turning it off is one-way.** The bucket has `prevent_destroy`, so once it exists, setting `audit_log_bucket_name` back to null fails the plan. Removing the archive takes a deliberate state removal, on purpose.
- **Region and trail name must agree between the two stacks.** The bucket policy names the trail ARN built from the security stack's region and the module's default trail name; the trail is created with the management stack's region and the other module's default name. A mismatch fails loudly at trail creation (`InsufficientS3BucketPolicy`).
- **Retention is cost-driven, not a compliance period.** Logs and their validation digests expire after 365 days, noncurrent versions after 90.

## Unverified until the first real plan

The list of S3 read actions of the CI roles on the log bucket (`live/accounts/security/audit_logs.tf`) is the set the AWS provider calls when it refreshes a bucket, written from its documentation and not yet exercised against a real bucket. A missing action shows up as `AccessDenied` in the plan of step 4 or in the next drift check, and is fixed by adding that one read action there and in its literal test.
