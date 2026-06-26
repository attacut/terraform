# AWS VPC Module

Terraform module สำหรับสร้าง VPC บน AWS พร้อม Subnet (public/private), Internet Gateway และ NAT Gateway

## Usage

```hcl
module "vpc" {
  source = "../../modules/aws/vpc"

  vpc_name = "my-app-vpc"
  vpc_cidr = "10.0.0.0/16"

  public_subnets = [
    {
      name = "public-a"
      cidr = "10.0.1.0/24"
      az   = "ap-southeast-1a"
    },
    {
      name = "public-b"
      cidr = "10.0.2.0/24"
      az   = "ap-southeast-1b"
    },
  ]

  private_subnets = [
    {
      name = "private-a"
      cidr = "10.0.11.0/24"
      az   = "ap-southeast-1a"
    },
    {
      name = "private-b"
      cidr = "10.0.12.0/24"
      az   = "ap-southeast-1b"
    },
  ]

  create_igw         = true
  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project     = "my-app"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vpc_name` | Name tag ของ VPC ที่ใช้ระบุใน AWS console | `string` | – | **yes** |
| `vpc_cidr` | CIDR block ของ VPC (เช่น `10.0.0.0/16`) ต้องเป็น IPv4 CIDR ที่ถูกต้อง | `string` | – | **yes** |
| `enable_dns_hostnames` | ให้ instance ที่มี public IP ได้รับ public DNS hostname อัตโนมัติ | `bool` | `true` | no |
| `enable_dns_support` | เปิดใช้ DNS resolver ของ AWS ภายใน VPC | `bool` | `true` | no |
| `public_subnets` | รายการ public subnet ที่จะสร้าง (ดู object schema ด้านล่าง) | `list(object)` | `[]` | no |
| `private_subnets` | รายการ private subnet ที่จะสร้าง (ดู object schema ด้านล่าง) | `list(object)` | `[]` | no |
| `create_igw` | สร้าง Internet Gateway หรือไม่ | `bool` | `true` | no |
| `enable_nat_gateway` | สร้าง NAT Gateway สำหรับ private subnet หรือไม่ | `bool` | `false` | no |
| `single_nat_gateway` | ใช้ NAT Gateway ตัวเดียวร่วมกัน แทนที่จะสร้างตามจำนวน public subnet | `bool` | `false` | no |
| `tags` | tag เพิ่มเติมที่ใส่ให้ทุก resource ในโมดูล | `map(string)` | `{}` | no |

### Subnet object schema

ทั้ง `public_subnets` และ `private_subnets` รับ list ของ object หน้าตาแบบนี้:

| Field | Description | Type | Required |
|-------|-------------|------|:--------:|
| `name` | ชื่อ (ใช้เป็น Name tag ของ subnet) | `string` | **yes** |
| `cidr` | CIDR block ของ subnet (ต้องอยู่ภายใน `vpc_cidr`) | `string` | **yes** |
| `az`   | Availability Zone เช่น `ap-southeast-1a` | `string` | **yes** |
| `tags` | tag เพิ่มเติมเฉพาะ subnet นี้ | `map(string)` | no (default `{}`) |

## NAT Gateway behavior

จำนวน NAT Gateway (และ Elastic IP) ขึ้นอยู่กับ flag ดังนี้:

| `enable_nat_gateway` | `single_nat_gateway` | จำนวน NAT Gateway ที่สร้าง |
|:--------------------:|:--------------------:|---------------------------|
| `false` | – | `0` |
| `true` | `true` | `1` (ตัวเดียวร่วมกัน) |
| `true` | `false` | เท่ากับจำนวน `public_subnets` |

> NAT Gateway จะถูกวางไว้ใน public subnet และต้องมี `public_subnets` อย่างน้อย 1 รายการเมื่อ `enable_nat_gateway = true`

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID ของ VPC |
| `vpc_arn` | ARN ของ VPC |
| `vpc_cidr` | CIDR block ของ VPC |
| `internet_gateway_id` | ID ของ Internet Gateway (`null` ถ้าไม่ได้สร้าง) |
| `public_subnet_ids` | list ของ ID ของ public subnet |
| `private_subnet_ids` | list ของ ID ของ private subnet |
| `nat_gateway_ids` | list ของ ID ของ NAT Gateway |
| `nat_eip_public_ips` | list ของ public IP ของ Elastic IP ที่ผูกกับ NAT Gateway |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.5.0` |
| aws provider | `>= 5.0` |
