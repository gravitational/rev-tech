resource "teleport_provision_token" "this" {
  version = "v2"
  metadata = {
    name = "${lower(var.name)}-iam-join-token"
  }

  spec = {
    roles       = ["App", "Node"]
    join_method = "iam"
    allow = [
      {
        aws_account = data.aws_caller_identity.this.account_id
      }
    ]
  }
}

resource "teleport_role" "this" {
  version = "v7"
  metadata = {
    name = var.name
  }

  spec = {
    allow = {
      app_labels = { "*" = ["*"] }

      aws_role_arns = [aws_iam_role.ro_access.arn]
    }
  }
}
