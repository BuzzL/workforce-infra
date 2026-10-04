# The demo account's own stack, applied by CI behind the approval of the demo GitHub Environment with
# the write permissions its baseline grants (bootstrap/accounts/demo, docs/ACCOUNT_CI_BASELINES.md).
# It owns no resources yet: the platform roles of docs/ENVIRONMENT_PERMISSIONS.md arrive with the
# change that first adds their permissions to the baseline ("CI permissions first", CLAUDE.md).
# The account's applications are not owned here: their own pipelines deploy them.
locals {
  environment = "demo"
  key         = "demo"
}
