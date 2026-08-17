output "instance_arn" {
  description = "The ARN of the IAM Identity Center instance in use"
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "The ID of the identity store backing the instance"
  value       = local.identity_store_id
}

output "user_ids" {
  description = "Map of user name to identity store user ID, covering both created and pre-existing users"
  value       = local.user_ids
}

output "group_ids" {
  description = "Map of group display name to identity store group ID, covering both created and pre-existing groups"
  value       = local.group_ids
}

output "permission_set_arns" {
  description = "Map of permission set name to its ARN"
  value       = { for name, ps in aws_ssoadmin_permission_set.this : name => ps.arn }
}

output "permission_set_ids" {
  description = "Map of permission set name to the ID segment of its ARN (the ps-xxxx part used in the AWS console)"
  value       = { for name, ps in aws_ssoadmin_permission_set.this : name => element(split("/", ps.arn), length(split("/", ps.arn)) - 1) }
}

output "account_assignments" {
  description = "The grants actually created, as a map of account_id|permission_set|principal_type|principal_name to its parts"
  value       = local.account_assignments
}

output "group_membership_ids" {
  description = "Map of group/user to the identity store membership ID"
  value       = { for key, m in aws_identitystore_group_membership.this : key => m.membership_id }
}
