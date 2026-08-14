# AWS IAM Module

Terraform module สำหรับสร้าง IAM Role บน AWS พร้อม trust policy, การแนบ managed/inline policy และ instance profile (optional)

## Usage

### EC2 instance role

```hcl
module "app_role" {
  source = "../../modules/aws/iam"

  role_name        = "my-app-ec2-role"
  role_description = "Role สำหรับ EC2 ของ my-app"

  trusted_services = ["ec2.amazonaws.com"]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  create_instance_profile = true

  tags = {
    Project     = "my-app"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### Lambda role พร้อม inline policy

```hcl
data "aws_iam_policy_document" "s3_read" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::my-bucket/*"]
  }
}

module "lambda_role" {
  source = "../../modules/aws/iam"

  role_name        = "my-app-lambda-role"
  trusted_services = ["lambda.amazonaws.com"]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
  ]

  inline_policies = {
    s3-read = data.aws_iam_policy_document.s3_read.json
  }
}
```

### Cross-account role

```hcl
module "cross_account_role" {
  source = "../../modules/aws/iam"

  role_name         = "ci-deployer"
  trusted_role_arns = ["arn:aws:iam::111122223333:root"]

  managed_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  permissions_boundary = "arn:aws:iam::444455556666:policy/DeveloperBoundary"
  max_session_duration = 7200
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `role_name` | ชื่อ IAM role ที่ใช้ระบุใน AWS console | `string` | – | **yes** |
| `role_description` | คำอธิบายของ role | `string` | `null` | no |
| `path` | path ที่ใช้สร้าง role และ instance profile (เช่น `/service-role/`) | `string` | `"/"` | no |
| `trusted_services` | AWS service principal ที่ assume role นี้ได้ (เช่น `["ec2.amazonaws.com"]`) | `list(string)` | `[]` | no |
| `trusted_role_arns` | ARN ของ user/role/account ที่ assume role นี้ได้ ใช้สำหรับ cross-account | `list(string)` | `[]` | no |
| `assume_role_policy` | trust policy JSON ดิบ **ทับ** `trusted_services` และ `trusted_role_arns` เมื่อระบุ | `string` | `null` | no |
| `managed_policy_arns` | ARN ของ managed policy ที่มีอยู่แล้ว ที่จะแนบกับ role | `list(string)` | `[]` | no |
| `inline_policies` | inline policy ที่ฝังใน role เป็น map ของ ชื่อ policy → policy JSON | `map(string)` | `{}` | no |
| `max_session_duration` | ระยะเวลาสูงสุดของ session ตอน assume role (วินาที) | `number` | `3600` | no |
| `permissions_boundary` | ARN ของ policy ที่ใช้เป็น permissions boundary ของ role | `string` | `null` | no |
| `force_detach_policies` | detach policy ทั้งหมดก่อนลบ role | `bool` | `false` | no |
| `create_instance_profile` | สร้าง instance profile หรือไม่ (จำเป็นถ้าจะแนบ role กับ EC2 instance) | `bool` | `false` | no |
| `tags` | tag เพิ่มเติมที่ใส่ให้ทุก resource ในโมดูล | `map(string)` | `{}` | no |

## Trust policy behavior

trust policy ถูกประกอบขึ้นตามลำดับความสำคัญนี้:

| เงื่อนไข | ผลลัพธ์ |
|---|---|
| ระบุ `assume_role_policy` | ใช้ JSON ที่ให้มาตรง ๆ ค่า `trusted_*` ทั้งหมดถูกมองข้าม |
| ระบุ `trusted_services` และ/หรือ `trusted_role_arns` | สร้าง statement `sts:AssumeRole` ให้อัตโนมัติ (service และ AWS principal แยกกันคนละ statement) |
| ไม่ระบุอะไรเลย | `terraform plan` **ล้มเหลว** ตั้งแต่ต้นด้วย precondition เพราะจะได้ role ที่ไม่มีใคร assume ได้ |

> `create_instance_profile` ใช้ได้กับ role ที่ trust `ec2.amazonaws.com` เท่านั้น instance profile จะใช้ชื่อและ path เดียวกับ role

## Outputs

| Name | Description |
|------|-------------|
| `role_id` | ID ของ IAM role |
| `role_arn` | ARN ของ IAM role |
| `role_name` | ชื่อของ IAM role |
| `role_unique_id` | unique ID ของ IAM role |
| `assume_role_policy` | trust policy JSON ที่แนบกับ role จริง |
| `attached_policy_arns` | list ของ ARN ของ managed policy ที่แนบไว้ |
| `inline_policy_names` | list ของชื่อ inline policy ที่ฝังไว้ |
| `instance_profile_name` | ชื่อ instance profile (`null` ถ้าไม่ได้สร้าง) |
| `instance_profile_arn` | ARN ของ instance profile (`null` ถ้าไม่ได้สร้าง) |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.11.0` |
| aws provider | `>= 5.0` |
