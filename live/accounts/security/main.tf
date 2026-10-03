# The security account's resources, applied by CI: Identity Center (identity.tf) and the audit
# log bucket (audit_logs.tf).
#
# The baseline (OIDC provider and the two CI roles) used to live in this stack. It moved to
# bootstrap/accounts/security, which is applied locally, so that the role CI applies with can
# never change itself. This block drops it from this stack's state without destroying anything;
# the other stack adopts the same resources (imports.tf there). After the first apply it has no
# effect; a later change removes it.
removed {
  from = module.baseline

  lifecycle {
    destroy = false
  }
}
