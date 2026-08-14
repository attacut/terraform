output "role_id" {
  description = "The ID of the IAM role"
  value       = aws_iam_role.this.id
}

output "role_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "The name of the IAM role"
  value       = aws_iam_role.this.name
}

output "role_unique_id" {
  description = "The stable and unique string identifying the IAM role"
  value       = aws_iam_role.this.unique_id
}

output "assume_role_policy" {
  description = "The trust policy JSON attached to the IAM role"
  value       = aws_iam_role.this.assume_role_policy
}

output "attached_policy_arns" {
  description = "List of managed policy ARNs attached to the IAM role"
  value       = [for a in aws_iam_role_policy_attachment.managed : a.policy_arn]
}

output "inline_policy_names" {
  description = "List of inline policy names embedded in the IAM role"
  value       = keys(aws_iam_role_policy.inline)
}

output "instance_profile_name" {
  description = "The name of the instance profile (null when create_instance_profile is false)"
  value       = try(aws_iam_instance_profile.this[0].name, null)
}

output "instance_profile_arn" {
  description = "The ARN of the instance profile (null when create_instance_profile is false)"
  value       = try(aws_iam_instance_profile.this[0].arn, null)
}
