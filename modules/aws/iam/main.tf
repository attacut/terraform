data "aws_iam_policy_document" "assume_role" {
  count = var.assume_role_policy == null ? 1 : 0

  dynamic "statement" {
    for_each = length(var.trusted_services) > 0 ? [1] : []

    content {
      sid     = "TrustedServices"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = var.trusted_services
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.trusted_role_arns) > 0 ? [1] : []

    content {
      sid     = "TrustedPrincipals"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = var.trusted_role_arns
      }
    }
  }
}

resource "aws_iam_role" "this" {
  name                  = var.role_name
  description           = var.role_description
  path                  = var.path
  assume_role_policy    = coalesce(var.assume_role_policy, one(data.aws_iam_policy_document.assume_role[*].json))
  max_session_duration  = var.max_session_duration
  permissions_boundary  = var.permissions_boundary
  force_detach_policies = var.force_detach_policies

  tags = merge(
    var.tags,
    {
      Name = var.role_name
    }
  )

  lifecycle {
    precondition {
      condition     = var.assume_role_policy != null || length(var.trusted_services) > 0 || length(var.trusted_role_arns) > 0
      error_message = "Set at least one of trusted_services, trusted_role_arns or assume_role_policy, otherwise nothing can assume the role."
    }
  }
}

# for_each keeps the attachments keyed by policy ARN, so removing one policy
# does not force the others to be recreated the way count indexes would.
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0

  name = var.role_name
  path = var.path
  role = aws_iam_role.this.name

  tags = merge(
    var.tags,
    {
      Name = var.role_name
    }
  )
}
