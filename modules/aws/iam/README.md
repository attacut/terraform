# AWS IAM Module

Terraform module สำหรับสร้าง IAM Role บน AWS

## เริ่มจากตรงนี้ก่อน: IAM Role ตอบ 2 คำถาม

การใช้โมดูลนี้ให้ถูก ต้องแยกให้ออกว่ากำลังตอบคำถามข้อไหนอยู่

```
      คำถามที่ 1: ใครสวม role นี้ได้              คำถามที่ 2: สวมแล้วทำอะไรได้ กับตัวไหน
      ┌──────────────────────────┐                ┌──────────────────────────────┐
      │  EC2 instance            │                │  s3:GetObject                │
      │  (ec2.amazonaws.com)     │                │  บน arn:aws:s3:::my-bucket/* │
      └────────────┬─────────────┘                └──────────────▲───────────────┘
                   │                                             │
                   │  sts:AssumeRole                             │  อนุญาตโดย
                   │  ผ่านได้ต่อเมื่อ trust policy ยอม             │  permission policy
                   │                                             │
                   └────────────►   IAM Role   ──────────────────┘
                                    my-app-role
```

| | คำถาม | ศัพท์ AWS | ตัวแปรในโมดูลนี้ |
|:--:|---|---|---|
| **1** | **ใคร** สวม role นี้ได้ | trust policy | `trusted_services`, `trusted_role_arns`, `assume_role_policy` |
| **2** | สวมแล้ว **ทำอะไรได้ กับ resource ตัวไหน** | permission policy | `managed_policy_arns`, `inline_policies` |

> [!IMPORTANT]
> **โมดูลนี้ไม่ได้เขียนสิทธิ์ให้คุณ** — คำถามข้อ 2 โมดูลทำหน้าที่แค่ "แนบ" policy ที่คุณส่งเข้ามาเท่านั้น
> คำตอบว่า *ได้อะไร กับ resource ตัวไหน* อยู่ในตัว policy ที่คุณส่งผ่าน `managed_policy_arns` หรือ `inline_policies` ทั้งหมด
> ถ้าไม่ส่งอะไรเลย จะได้ role ที่ assume ได้แต่ทำอะไรไม่ได้สักอย่าง

## วิธีอ่าน permission policy

policy หนึ่งใบประกอบด้วย statement ที่ตอบว่า "ทำอะไร (Action) กับตัวไหน (Resource)"

```hcl
data "aws_iam_policy_document" "s3_read" {
  statement {
    effect    = "Allow"                            # อนุญาต หรือ ปฏิเสธ
    actions   = ["s3:GetObject"]                   # ทำอะไรได้      ← "ได้อะไร"
    resources = ["arn:aws:s3:::my-bucket/*"]       # กับ resource ไหน ← "ที่ตัวไหน"
  }
}
```

`resources` คือจุดที่กำหนดขอบเขต ตัวอย่างความต่าง:

| `resources` | ความหมาย |
|---|---|
| `["arn:aws:s3:::my-bucket/*"]` | ทุก object ใน bucket เดียวนี้ |
| `["arn:aws:s3:::my-bucket"]` | ตัว bucket เอง (เช่น `s3:ListBucket`) ไม่รวม object ข้างใน |
| `["*"]` | **ทุก resource ในบัญชี** — ควรหลีกเลี่ยง |

> `s3:GetObject` ต้องการ ARN ระดับ object (`/*`) ส่วน `s3:ListBucket` ต้องการ ARN ระดับ bucket (ไม่มี `/*`) เป็นสาเหตุที่ทำให้ policy พังบ่อยที่สุด

## managed policy vs inline policy — เลือกยังไง

| | `managed_policy_arns` | `inline_policies` |
|---|---|---|
| คืออะไร | policy ที่มีตัวตนแยกอยู่แล้ว (ของ AWS หรือที่คุณสร้างเอง) | policy ที่ฝังอยู่ในตัว role |
| ขอบเขต resource | **ถูกกำหนดมาแล้ว** คุณควบคุมไม่ได้ | **คุณเขียนเอง** ระบุ ARN ได้ตรงตัว |
| ใช้ซ้ำ | แนบให้หลาย role ได้ | ผูกกับ role นี้เท่านั้น |
| ตอนลบ role | policy ยังอยู่ | หายไปพร้อม role |
| เหมาะกับ | สิทธิ์มาตรฐาน เช่น `AWSLambdaBasicExecutionRole` | สิทธิ์เฉพาะงาน ที่ต้องจำกัดถึง resource ตัวใดตัวหนึ่ง |

ถ้าต้องการจำกัดว่า "ได้เฉพาะ bucket นี้ / table นี้" → ใช้ `inline_policies`

## Usage

### 1. EC2 instance role

```hcl
module "app_role" {
  source = "../../modules/aws/iam"

  role_name = "my-app-ec2-role"

  # ── ใคร: EC2 instance สวม role นี้ได้
  trusted_services = ["ec2.amazonaws.com"]

  # ── ได้อะไร: เชื่อมต่อ SSM Session Manager ได้ (policy ของ AWS ขอบเขตกว้าง คุมไม่ได้)
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]

  # ต้องเปิด ถึงจะเอา role ไปแปะกับ EC2 instance ได้
  create_instance_profile = true

  tags = { Project = "my-app" }
}
```

**สรุปสิทธิ์ที่ได้:** EC2 instance ที่แปะ profile นี้ → คุยกับ SSM endpoint ได้ → เข้า Session Manager ได้ โดยไม่ต้องเปิด SSH

```hcl
resource "aws_instance" "app" {
  # ...
  iam_instance_profile = module.app_role.instance_profile_name
}
```

### 2. Lambda role ที่จำกัดถึง bucket ตัวเดียว

```hcl
data "aws_iam_policy_document" "app_data" {
  statement {
    sid       = "ReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::my-app-data/*"]      # เฉพาะ object ใน bucket นี้
  }

  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::my-app-data"]        # ตัว bucket เอง (ไม่มี /*)
  }
}

module "lambda_role" {
  source = "../../modules/aws/iam"

  role_name = "my-app-lambda-role"

  # ── ใคร: Lambda service
  trusted_services = ["lambda.amazonaws.com"]

  # ── ได้อะไร (1): เขียน log ลง CloudWatch
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
  ]

  # ── ได้อะไร (2): อ่าน S3 เฉพาะ my-app-data เท่านั้น
  inline_policies = {
    app-data-read = data.aws_iam_policy_document.app_data.json
  }
}
```

**สรุปสิทธิ์ที่ได้:**

| ทำอะไรได้ | กับ resource ไหน | มาจาก |
|---|---|---|
| `logs:CreateLogStream`, `logs:PutLogEvents` | log group ของ Lambda | managed: `AWSLambdaBasicExecutionRole` |
| `s3:GetObject` | `my-app-data/*` เท่านั้น | inline: `app-data-read` |
| `s3:ListBucket` | `my-app-data` เท่านั้น | inline: `app-data-read` |
| อย่างอื่นทั้งหมด | — | **ถูกปฏิเสธ** (IAM ปฏิเสธเป็นค่าเริ่มต้น) |

### 3. Cross-account role

```hcl
module "ci_role" {
  source = "../../modules/aws/iam"

  role_name = "ci-deployer"

  # ── ใคร: ทุก principal ในบัญชี 111122223333 ที่ได้รับสิทธิ์จากฝั่งนั้นด้วย
  trusted_role_arns = ["arn:aws:iam::111122223333:root"]

  # ── ได้อะไร: อ่านได้ทุกอย่างในบัญชีนี้
  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  # เพดานสิทธิ์: ต่อให้แนบ policy แรงแค่ไหน ก็ทำได้ไม่เกิน boundary นี้
  permissions_boundary = "arn:aws:iam::444455556666:policy/DeveloperBoundary"

  max_session_duration = 7200   # session อยู่ได้ 2 ชั่วโมง
}
```

> `:root` **ไม่ได้** แปลว่า root user แต่แปลว่า "มอบสิทธิ์การตัดสินใจให้บัญชีนั้นไปจัดการเอง" — principal ฝั่งนั้นยังต้องมี `sts:AssumeRole` ใน policy ของตัวเองด้วย ถึงจะ assume ได้จริง

## ลำดับความสำคัญของ trust policy

| เงื่อนไข | ผลลัพธ์ |
|---|---|
| ระบุ `assume_role_policy` | ใช้ JSON นั้นตรง ๆ ค่า `trusted_*` ทั้งหมดถูกมองข้าม |
| ระบุ `trusted_services` และ/หรือ `trusted_role_arns` | โมดูลสร้าง statement `sts:AssumeRole` ให้ (service กับ AWS principal แยกกันคนละ statement) |
| ไม่ระบุอะไรเลย | `terraform plan` **ล้มเหลวทันที** ด้วย precondition เพราะจะได้ role ที่ไม่มีใคร assume ได้ |

## ตรวจสอบหลัง apply

ดู trust policy ที่แนบจริง (ใครสวมได้บ้าง):

```bash
terraform output -raw assume_role_policy | jq
```

ทดสอบว่า role ทำ action นั้นกับ resource นั้นได้จริงไหม โดยไม่ต้องยิงของจริง:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn "$(terraform output -raw role_arn)" \
  --action-names s3:GetObject \
  --resource-arns "arn:aws:s3:::my-app-data/some-key" \
  --query 'EvaluationResults[].EvalDecision'
```

## Inputs

**ตอบคำถามข้อ 1 — ใครสวม role นี้ได้**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `trusted_services` | AWS service principal ที่ assume role ได้ เช่น `["ec2.amazonaws.com"]`, `["lambda.amazonaws.com"]` | `list(string)` | `[]` | no |
| `trusted_role_arns` | ARN ของ user/role/account ที่ assume role ได้ ใช้กับ cross-account | `list(string)` | `[]` | no |
| `assume_role_policy` | trust policy JSON ดิบ **ทับ** สองตัวข้างบนเมื่อระบุ ใช้เมื่อต้องการ condition ซับซ้อน เช่น OIDC | `string` | `null` | no |

**ตอบคำถามข้อ 2 — ทำอะไรได้ กับ resource ไหน**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `managed_policy_arns` | ARN ของ managed policy ที่มีอยู่แล้ว ขอบเขต resource ถูกกำหนดมาในตัว policy | `list(string)` | `[]` | no |
| `inline_policies` | policy ที่ฝังใน role เป็น map ของ ชื่อ policy → policy JSON ใช้เมื่อต้องระบุ resource ARN เอง | `map(string)` | `{}` | no |
| `permissions_boundary` | ARN ของ policy ที่เป็น**เพดาน**สิทธิ์ สิทธิ์จริง = policy ที่แนบ ∩ boundary | `string` | `null` | no |

**ตัวตนและพฤติกรรมของ role**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `role_name` | ชื่อ IAM role ที่ใช้ระบุใน AWS console | `string` | – | **yes** |
| `role_description` | คำอธิบายของ role | `string` | `null` | no |
| `path` | path ที่ใช้สร้าง role และ instance profile เช่น `/service-role/` | `string` | `"/"` | no |
| `max_session_duration` | ระยะเวลาสูงสุดของ session ตอน assume role (วินาที, 3600–43200) | `number` | `3600` | no |
| `create_instance_profile` | สร้าง instance profile หรือไม่ — **ต้องเปิดถ้าจะแนบ role กับ EC2** | `bool` | `false` | no |
| `force_detach_policies` | detach policy ทั้งหมดก่อนลบ role | `bool` | `false` | no |
| `tags` | tag เพิ่มเติมที่ใส่ให้ทุก resource ในโมดูล | `map(string)` | `{}` | no |

> instance profile จะใช้ชื่อและ path เดียวกับ role และใช้ได้เฉพาะกับ role ที่ trust `ec2.amazonaws.com`

## Outputs

| Name | Description | ใช้ตอนไหน |
|------|-------------|-----------|
| `role_arn` | ARN ของ IAM role | ส่งให้ service อื่นอ้างถึง role นี้ |
| `role_name` | ชื่อของ IAM role | แนบ policy เพิ่มจากนอกโมดูล |
| `role_id` | ID ของ IAM role | — |
| `role_unique_id` | unique ID ของ role (`AROA...`) | อ้างใน policy condition |
| `instance_profile_name` | ชื่อ instance profile (`null` ถ้าไม่ได้สร้าง) | ใส่ใน `aws_instance.iam_instance_profile` |
| `instance_profile_arn` | ARN ของ instance profile (`null` ถ้าไม่ได้สร้าง) | ใช้กับ launch template |
| `assume_role_policy` | trust policy JSON ที่แนบจริง | ตรวจสอบว่าใครสวมได้บ้าง |
| `attached_policy_arns` | list ของ managed policy ARN ที่แนบไว้ | ตรวจสอบสิทธิ์ |
| `inline_policy_names` | list ของชื่อ inline policy | ตรวจสอบสิทธิ์ |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.11.0` |
| aws provider | `>= 5.0` |
