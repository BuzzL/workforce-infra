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
- **SSE-S3, no customer-managed KMS key.** A key costs money every month and adds a key policy that can lock the logs away. Log file validation digests prove the logs were not altered. Trivy AWS-0015 is waived in code with this reason.
- **The bucket policy names the exact trail ARN** (`aws:SourceArn`), so no other trail, in this Organization or elsewhere, can write to it.

## Order of rollout

The trail cannot exist before its bucket accepts it, so the steps are ordered. Every step that creates a billable resource needs the maintainer's explicit yes.

1. Enable trusted access for CloudTrail in the Organization, once, from the management SSO admin session: `aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com`.
2. Set the secrets `AUDIT_LOG_BUCKET` (a globally unique bucket name), `ORGANIZATION_ID` and `MANAGEMENT_ACCOUNT_ID` on the `security` and `security-plan` GitHub Environments, and `AUDIT_LOG_BUCKET` on `management` and `management-plan`. They are secrets because the repository is public.
3. Apply `live/accounts/security` (gated CI): creates the bucket.
4. Apply `live/management` (gated CI): creates the trail.

## Not decided yet

- **Protection against deleting logs or the trail.** A bucket Deny on `s3:DeleteObject*` or on stopping the trail that excepts only the break-glass path could lock out a principal, so it needs the maintainer's explicit approval and its own PR with a literal test.
- **CI permissions to create these resources.** The apply roles of `security` and `management` do not yet allow S3 bucket or CloudTrail management; adding them is a separate, reviewed change.
