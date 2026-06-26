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
  description = "instance ที่มี public IP ได้รับ public DNS hostname อัตโนมัติ"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "DNS resolver ของ AWS"
  type        = bool
  default     = true
}

variable "private_subnets" {
  description = "List of private subnets to create in the VPC"
  type = list(object({
    name = string
    cidr = string
    az   = string
    tags = optional(map(string), {})
  }))
  default = []
}

variable "public_subnets" {
  description = "List of public subnets to create in the VPC"
  type = list(object({
    name = string
    cidr = string
    az   = string
    tags = optional(map(string), {})
  }))
  default = []
}

variable "create_igw" {
  description = "Whether to create an Internet Gateway"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT Gateway(s) for the private subnets"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway instead of one per public subnet"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}