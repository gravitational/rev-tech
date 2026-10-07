# Plan-only checks for the AWS Console wiring, with every provider mocked so
# no cloud or Teleport credentials are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}
mock_provider "teleport" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "http" {}

variables {
  proxy_address      = "acme.example.com"
  user               = "sam@example.com"
  profile_label      = "aws-console"
  enable_aws_console = true
}

run "console_roles_are_created_and_granted" {
  command = plan

  assert {
    condition     = aws_iam_role.console["ReadOnly"].name == "sam-aws-console-dev-console-ReadOnly"
    error_message = "the ReadOnly console role should be named <user>-<profile>-<env>-console-ReadOnly"
  }
  assert {
    condition     = length(output.aws_role_arns) == 1 && output.aws_role_arns[0] == "arn:aws:iam::123456789012:role/sam-aws-console-dev-console-ReadOnly"
    error_message = "aws_role_arns should carry exactly the created role's ARN"
  }
  assert {
    condition     = aws_iam_role_policy_attachment.console["ReadOnly|arn:aws:iam::aws:policy/ReadOnlyAccess"].policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "the ReadOnly role should carry ReadOnlyAccess"
  }
}

run "extra_existing_roles_are_appended" {
  command = plan

  variables {
    console_role_arns = ["arn:aws:iam::123456789012:role/Existing"]
  }

  assert {
    condition     = length(output.aws_role_arns) == 2 && output.aws_role_arns[1] == "arn:aws:iam::123456789012:role/Existing"
    error_message = "console_role_arns should follow the created roles"
  }
}

run "nothing_when_console_is_off" {
  command = plan

  variables {
    enable_aws_console = false
  }

  assert {
    condition     = length(aws_iam_role.console) == 0 && length(output.aws_role_arns) == 0
    error_message = "no console roles or ARNs without enable_aws_console"
  }
}
