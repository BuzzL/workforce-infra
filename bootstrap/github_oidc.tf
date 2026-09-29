# One OIDC provider per account. No thumbprint: AWS validates GitHub's certificate chain
# against its trusted CAs.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
