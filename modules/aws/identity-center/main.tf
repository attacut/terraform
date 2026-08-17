data "aws_ssoadmin_instances" "this" {
  count = var.instance_arn == null || var.identity_store_id == null ? 1 : 0
}

locals {
  instance_arn      = var.instance_arn != null ? var.instance_arn : one(data.aws_ssoadmin_instances.this[0].arns)
  identity_store_id = var.identity_store_id != null ? var.identity_store_id : one(data.aws_ssoadmin_instances.this[0].identity_store_ids)
}

check "identity_center_enabled" {
  assert {
    condition     = local.instance_arn != null && local.identity_store_id != null
    error_message = "No IAM Identity Center instance found. Enable Identity Center in the organization management account (or in this account for an account instance) before applying this module."
  }
}

# ---------------------------------------------------------------------------
# Identity store — who exists
# ---------------------------------------------------------------------------

resource "aws_identitystore_user" "this" {
  for_each = var.users

  identity_store_id = local.identity_store_id
  user_name         = each.key
  display_name      = coalesce(each.value.display_name, "${each.value.given_name} ${each.value.family_name}")

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  dynamic "emails" {
    for_each = each.value.email != null ? [each.value.email] : []

    content {
      value   = emails.value
      primary = true
    }
  }
}

resource "aws_identitystore_group" "this" {
  for_each = var.groups

  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value.description
}

# Names referenced by memberships and assignments that this module does not
# create are assumed to exist already — the usual case when an external IdP
# provisions the identity store over SCIM.
locals {
  referenced_users = toset(concat(
    flatten([for g in var.groups : g.members]),
    flatten([for a in var.assignments : a.users]),
  ))

  referenced_groups = toset(flatten([for a in var.assignments : a.groups]))

  external_users  = setsubtract(local.referenced_users, keys(var.users))
  external_groups = setsubtract(local.referenced_groups, keys(var.groups))
}

data "aws_identitystore_user" "external" {
  for_each = local.external_users

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value
    }
  }
}

data "aws_identitystore_group" "external" {
  for_each = local.external_groups

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

locals {
  user_ids = merge(
    { for name, u in aws_identitystore_user.this : name => u.user_id },
    { for name, u in data.aws_identitystore_user.external : name => u.user_id },
  )

  group_ids = merge(
    { for name, g in aws_identitystore_group.this : name => g.group_id },
    { for name, g in data.aws_identitystore_group.external : name => g.group_id },
  )

  group_memberships = {
    for m in flatten([
      for group_name, group in var.groups : [
        for user_name in group.members : {
          group = group_name
          user  = user_name
        }
      ]
    ]) : "${m.group}/${m.user}" => m
  }
}

resource "aws_identitystore_group_membership" "this" {
  for_each = local.group_memberships

  identity_store_id = local.identity_store_id
  group_id          = local.group_ids[each.value.group]
  member_id         = local.user_ids[each.value.user]
}

# ---------------------------------------------------------------------------
# Permission sets — what a principal may do once inside an account
# ---------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  instance_arn     = local.instance_arn
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration
  relay_state      = each.value.relay_state

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = each.key
    }
  )
}

# Flattened so a policy list stays keyed by permission set and ARN — dropping
# one policy leaves the other attachments untouched.
locals {
  managed_policy_attachments = {
    for a in flatten([
      for name, ps in var.permission_sets : [
        for arn in ps.managed_policy_arns : {
          permission_set = name
          policy_arn     = arn
        }
      ]
    ]) : "${a.permission_set}|${a.policy_arn}" => a
  }

  customer_managed_policy_attachments = {
    for a in flatten([
      for name, ps in var.permission_sets : [
        for policy in ps.customer_managed_policies : {
          permission_set = name
          policy_name    = policy.name
          policy_path    = policy.path
        }
      ]
    ]) : "${a.permission_set}|${a.policy_path}${a.policy_name}" => a
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.managed_policy_attachments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.policy_arn
}

# The referenced policy must exist, under the same name and path, in every
# account the permission set is assigned to.
resource "aws_ssoadmin_customer_managed_policy_attachment" "this" {
  for_each = local.customer_managed_policy_attachments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn

  customer_managed_policy_reference {
    name = each.value.policy_name
    path = each.value.policy_path
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = { for name, ps in var.permission_sets : name => ps if ps.inline_policy != null }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value.inline_policy
}

resource "aws_ssoadmin_permissions_boundary_attachment" "this" {
  for_each = { for name, ps in var.permission_sets : name => ps if ps.permissions_boundary != null }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  permissions_boundary {
    managed_policy_arn = each.value.permissions_boundary.managed_policy_arn

    dynamic "customer_managed_policy_reference" {
      for_each = each.value.permissions_boundary.customer_managed_policy_reference != null ? [each.value.permissions_boundary.customer_managed_policy_reference] : []

      content {
        name = customer_managed_policy_reference.value.name
        path = customer_managed_policy_reference.value.path
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Account assignments — who gets which permission set, on which account
# ---------------------------------------------------------------------------

locals {
  account_assignments = {
    # distinct() first: the same grant written under two labels is one
    # assignment in AWS, and duplicate map keys are an error in Terraform.
    for a in distinct(flatten([
      for _, assignment in var.assignments : [
        for account_id in assignment.account_ids : concat(
          [for group_name in assignment.groups : {
            permission_set = assignment.permission_set
            principal_type = "GROUP"
            principal_name = group_name
            account_id     = account_id
          }],
          [for user_name in assignment.users : {
            permission_set = assignment.permission_set
            principal_type = "USER"
            principal_name = user_name
            account_id     = account_id
          }],
        )
      ]
      # Keyed by the grant itself rather than by the map key, so relabelling an
      # assignment does not destroy and recreate it.
    ])) : "${a.account_id}|${a.permission_set}|${a.principal_type}|${a.principal_name}" => a
  }
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.account_assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = each.value.principal_type
  principal_id       = each.value.principal_type == "GROUP" ? local.group_ids[each.value.principal_name] : local.user_ids[each.value.principal_name]
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account_id
}

# ---------------------------------------------------------------------------
# ABAC — identity store attributes passed into the session as tags
# ---------------------------------------------------------------------------

resource "aws_ssoadmin_instance_access_control_attributes" "this" {
  count = length(var.access_control_attributes) > 0 ? 1 : 0

  instance_arn = local.instance_arn

  dynamic "attribute" {
    for_each = var.access_control_attributes

    content {
      key = attribute.key

      value {
        source = attribute.value
      }
    }
  }
}
