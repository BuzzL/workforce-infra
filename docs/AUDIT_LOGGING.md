# Audit logging: organization trail and log archive

Every API call in every account is recorded by one organization trail and kept in a bucket the other accounts cannot reach. It also gives the SCP that denies disabling logging something to protect.

## What exists

| Piece | Where | Code |
|---|---|---|
| Log bucket: private, versioned, SSE-S3, lifecycle, TLS-only Deny, Allows only for the one trail ARN | `security` account | `modules/audit-log-bucket`, wired in `live/accounts/security/audit_logs.tf` |
| Organization trail: single region, log file validation, global service events, management events only | `management` account | `modules/organization-trail`, wired in `live/management/audit_logs.tf` |

Both stacks keep the feature **off** while `audit_log_bucket_name` is unset or empty, so merging the code creates nothing. Creating the trail needs trusted access for `cloudtrail.amazonaws.com` in the Organization, enabled once by hand. The apply role may repeat it for that one service principal only (`organizations:EnableAWSServiceAccess` with a `organizations:ServicePrincipal` condition), because AWS documents that the principal creating an organization trail needs this permission.

## Prerequisites in the management account

- The service-linked role `AWSServiceRoleForCloudTrail`, managed by `live/management/service_linked_role.tf` (imported, `prevent_destroy`). The first apply of the trail failed until it existed; why CloudTrail could not create it itself under the CI role was not identified. In a rebuilt account, create it first (`aws iam create-service-linked-role --aws-service-name cloudtrail.amazonaws.com`), then apply.

## Decisions

- **Single region.** The region-deny SCP leaves one region in use (`docs/ORGANIZATIONS.md`), so a multi-region trail would only add cost. Global service events (IAM, STS) are recorded in the home region.
- **Management events only.** The first copy of management events is free; data events are billed per event and are not enabled.
- **SSE-S3, no customer-managed KMS key.** A key costs money every month and adds a key policy that can lock the logs away. Log file validation digests prove the logs were not altered. Trivy AWS-0015 (trail) and AVD-AWS-0132 (bucket) are waived in code with this reason, the same as the state bucket. Only HIGH and CRITICAL findings gate CI; lower severities such as bucket access logging and CloudWatch integration of the trail are not evaluated.
- **Deleting logs is denied to everyone but the break-glass role.** The bucket policy denies `s3:DeleteObject`, `s3:DeleteObjectVersion` and `s3:DeleteBucket` unless `aws:PrincipalArn` is `OrganizationAccountAccessRole` of `security` (the maintainer approved this Deny). Lifecycle expiry is done by S3 itself and is not affected. `PutBucketPolicy` is deliberately not denied: that would lock Terraform and the account root out of the only way to repair the policy. The root user can still edit the policy, which is the recovery path.
- **CI can neither delete the trail nor stop it.** The apply role of `management` is not granted `cloudtrail:DeleteTrail` or `cloudtrail:StopLogging`, so only an admin session can. It does hold `cloudtrail:UpdateTrail`, which can still alter the trail (another bucket, validation off): that is guarded by review and by the approval of the `management` environment, not by IAM. SCPs do not apply to the management account, so IAT-36's "deny disabling logging" protects the member accounts only.
- **The bucket policy names the exact trail ARN** (`aws:SourceArn`), so no other trail, in this Organization or elsewhere, can write to it.
