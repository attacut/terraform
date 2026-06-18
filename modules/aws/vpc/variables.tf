variable "vpc_name" {
  description = "Name tag for the VPC, used to identify it in the AWS console"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "enable_dns_hostnames" {
  description = "Whether instances in the VPC get public DNS hostnames"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Whether to enable DNS resolution through the Amazon-provided DNS server"
  type        = bool
  default     = true
}

variable "create_igw" {
  description = "Whether to create an Internet Gateway"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}