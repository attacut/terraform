variable "instance_arn" {
  description = "ARN of the IAM Identity Center instance. Discovered automatically when null"
  type        = string
  default     = null
}

variable "identity_store_id" {
  description = "ID of the identity store backing the instance. Discovered automatically when null"
  type        = string
  default     = null
}

variable "users" {
  description = "Users to create in the identity store, keyed by user name. Leave empty when users are provisioned by an external IdP over SCIM"
  type = map(object({
    display_name = optional(string)
    given_name   = string
    family_name  = string
    email        = optional(string)
  }))
  default = {}
}

variable "groups" {
  description = "Groups to create in the identity store, keyed by display name. `members` holds user names, which may belong to this module or already exist in the store"
  type = map(object({
    description = optional(string)
    members     = optional(list(string), [])
  }))
  default = {}
}

variable "permission_sets" {
  description = "Permission sets to create, keyed by name. Answers what a principal may do once it opens an account"
  type = map(object({
    description      = optional(string)
    session_duration = optional(string, "PT1H")
    relay_state      = optional(string)

    managed_policy_arns = optional(list(string), [])
    customer_managed_policies = optional(list(object({
      name = string
      path = optional(string, "/")
    })), [])
    inline_policy = optional(string)

    permissions_boundary = optional(object({
      managed_policy_arn = optional(string)
      customer_managed_policy_reference = optional(object({
        name = string
        path = optional(string, "/")
      }))
    }))

    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.permission_sets) : length(name) <= 32])
    error_message = "Permission set names are limited to 32 characters by AWS."
  }

  # AWS accepts 1 minute to 12 hours, so the hour and minute parts are summed
  # rather than range-checked one by one (PT90M is as valid as PT1H30M).
  validation {
    condition = alltrue([
      for ps in var.permission_sets :
      can(regex("^PT([0-9]+H)?([0-9]+M)?$", ps.session_duration)) && try(contains(range(1, 721), sum([
        for part in regexall("[0-9]+[HM]", ps.session_duration) :
        endswith(part, "H") ? tonumber(trimsuffix(part, "H")) * 60 : tonumber(trimsuffix(part, "M"))
      ])), false)
    ])
    error_message = "session_duration must be an ISO-8601 duration totalling between 1 minute and 12 hours (e.g. PT1H, PT30M, PT8H, PT1H30M)."
  }

  validation {
    condition = alltrue([
      for ps in var.permission_sets :
      ps.permissions_boundary == null ? true :
      (ps.permissions_boundary.managed_policy_arn == null) != (ps.permissions_boundary.customer_managed_policy_reference == null)
    ])
    error_message = "permissions_boundary takes exactly one of managed_policy_arn or customer_managed_policy_reference."
  }
}

variable "assignments" {
  description = "Grants of a permission set to principals on a set of accounts. The map key is a label of your choosing and does not reach AWS"
  type = map(object({
    permission_set = string
    groups         = optional(list(string), [])
    users          = optional(list(string), [])
    account_ids    = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for a in var.assignments : contains(keys(var.permission_sets), a.permission_set)])
    error_message = "Every assignment must reference a permission set declared in var.permission_sets."
  }

  validation {
    condition     = alltrue([for a in var.assignments : length(a.groups) + length(a.users) > 0])
    error_message = "Every assignment needs at least one entry in groups or users, otherwise it grants nothing."
  }

  validation {
    condition     = alltrue([for a in var.assignments : alltrue([for id in a.account_ids : can(regex("^[0-9]{12}$", id))])])
    error_message = "account_ids must be 12-digit AWS account IDs."
  }
}

variable "access_control_attributes" {
  description = "ABAC attributes exposed as session tags, as a map of attribute key to identity store source paths (e.g. { Team = [\"$${path:enterprise.department}\"] })"
  type        = map(list(string))
  default     = {}
}

variable "tags" {
  description = "Additional tags to apply to every permission set created by this module"
  type        = map(string)
  default     = {}
}
