terraform {
  required_version = ">= 1.11.0"   # ดันขึ้นจาก 1.5.0 เพื่อรองรับ use_lockfile
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}