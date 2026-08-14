variable "role_name" {
  description = "Name of the IAM role, used to identify it in the AWS console"
  type        = string
}

variable "role_description" {
  description = "Description of the IAM role"
  type        = string
  default     = null
}

variable "path" {
  description = "Path under which to create the role and instance profile (e.g. /service-role/)"
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.path, "/") && endswith(var.path, "/")
    error_message = "path must begin and end with a forward slash (e.g. / or /service-role/)."
  }
}

variable "trusted_services" {
  description = "AWS service principals allowed to assume this role (e.g. [\"ec2.amazonaws.com\"])"
  type        = list(string)
  default     = []
}

variable "trusted_role_arns" {
  description = "IAM user/role/account ARNs allowed to assume this role, for cross-account access"
  type        = list(string)
  default     = []
}

variable "assume_role_policy" {
  description = "Raw trust policy JSON. Overrides trusted_services and trusted_role_arns when set"
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "ARNs of existing managed policies to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Inline policies to embed in the role, as a map of policy name to policy JSON"
  type        = map(string)
  default     = {}
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds when assuming the role"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "permissions_boundary" {
  description = "ARN of the policy used as the permissions boundary for the role"
  type        = string
  default     = null
}

variable "force_detach_policies" {
  description = "Detach all attached policies before destroying the role"
  type        = bool
  default     = false
}

variable "create_instance_profile" {
  description = "Whether to create an instance profile for the role, required to attach it to an EC2 instance"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}
