# The four baseline SCPs (modules/scp-baseline). The module only defines them: they are
# attached by attachments.tf, one organizational unit at a time.
module "scp_baseline" {
  source = "../../modules/scp-baseline"

  allowed_region = var.region
  tags           = var.tags
}
