data "aws_iam_policy_document" "pass_role" {
  statement {
    effect = "Allow"

    actions = ["iam:PassRole"]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      values   = ["ec2.amazonaws.com"]
      variable = "iam:PassedToService"
    }

  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "this" {
  name   = "${lower(var.name)}-policy"
  policy = data.aws_iam_policy_document.pass_role.json
  tags   = local.tags
}

resource "aws_iam_role" "this" {
  name               = "${lower(var.name)}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = aws_iam_policy.this.arn
  role       = aws_iam_role.this.name
}

resource "aws_iam_instance_profile" "this" {
  name = "${lower(var.name)}-profile"
  role = aws_iam_role.this.name
  tags = local.tags
}

data "aws_iam_policy" "read_only_access" {
  name = "ReadOnlyAccess"
}

data "aws_iam_policy_document" "read_only_access_assume_role" {
  statement {
    effect = "Allow"

    principals {
      identifiers = [aws_iam_role.this.arn]
      type        = "AWS"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ro_access" {
  name               = "${lower(var.name)}-ro_access-role"
  assume_role_policy = data.aws_iam_policy_document.read_only_access_assume_role.json
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ro_access" {
  policy_arn = data.aws_iam_policy.read_only_access.arn
  role       = aws_iam_role.ro_access.name
}

data "aws_iam_policy_document" "assume_example_readonly_role" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.ro_access.arn]
  }
}

resource "aws_iam_policy" "teleport_aws_access" {
  name   = "${var.name}-teleport_aws_access-policy"
  policy = data.aws_iam_policy_document.assume_example_readonly_role.json
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "teleport_aws_access" {
  policy_arn = aws_iam_policy.teleport_aws_access.arn
  role       = aws_iam_role.this.name
}

