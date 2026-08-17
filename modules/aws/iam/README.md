# AWS IAM Module

## Identity providers 

Trust Relationship trust token ที่ออกโดย issuer เจ้าไหนบ้าง

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

### 4. ให้ทีม developer อ่าน log (human access)

ต่างจาก 3 เคสบนตรงที่ผู้ใช้เป็น **คน** ไม่ใช่ service — หลักการคือ **ให้ assume role ไม่ใช่แนบ policy ที่ user ตรง ๆ**

```
┌─────────────────┐   sts:AssumeRole    ┌──────────────────┐   permission    ┌─────────────────┐
│ IAM user        │ ──────────────────► │ Role             │ ──────────────► │ CloudWatch Logs │
│ ในกลุ่ม dev      │                     │ developer-log-   │                 │ /aws/lambda/    │
│ (alice, bob)    │  ต้องผ่าน MFA        │ reader           │  อ่านอย่างเดียว   │ my-app*         │
└─────────────────┘                     └──────────────────┘                 └─────────────────┘
   ต้องมีสิทธิ์                             trust policy                        inline policy
   assume ฝั่งตัวเอง                        คุมว่าใครสวมได้                      คุมว่าอ่านอะไรได้
```

ข้อดีเทียบกับแนบ policy ที่ user ตรง ๆ: สิทธิ์เป็น session ชั่วคราวที่หมดอายุเอง, บังคับ MFA ได้, เพิ่ม/ลดคนแก้ที่เดียว, และ CloudTrail เห็นว่าใคร assume เมื่อไหร่

**ฝั่ง "ได้อะไร"** — ต้องแยก 2 statement เพราะบาง action ของ CloudWatch Logs จำกัด resource ไม่ได้

```hcl
data "aws_caller_identity" "current" {}

locals {
  log_group_prefix = "/aws/lambda/my-app" # ปรับให้ตรงกับแอปของทีม
  log_group_arn    = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_prefix}*"
}

data "aws_iam_policy_document" "log_reader" {
  # action ที่จำกัด log group ได้
  statement {
    sid    = "ReadScopedLogGroups"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
    ]
    resources = [
      local.log_group_arn,                   # ตัว log group
      "${local.log_group_arn}:log-stream:*", # log stream ข้างใน
    ]
  }

  # action ที่ AWS ไม่รองรับ resource-level ต้องใช้ "*"
  # ปลอดภัยเพราะดึงผลได้เฉพาะ query ที่ตัวเองเริ่ม ซึ่งถูกจำกัดด้วย StartQuery ข้างบนแล้ว
  statement {
    sid    = "LogsInsightsResults"
    effect = "Allow"
    actions = [
      "logs:GetQueryResults",
      "logs:StopQuery",
      "logs:DescribeQueries",
      "logs:GetLogRecord",
    ]
    resources = ["*"]
  }
}
```

**ฝั่ง "ใคร"** — คนควรบังคับ MFA เสมอ ซึ่งต้องใช้ `assume_role_policy` แบบ raw เพราะ `trusted_role_arns` ยังใส่ condition ไม่ได้

```hcl
data "aws_iam_policy_document" "dev_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

module "developer_log_reader" {
  source = "../../modules/aws/iam"

  role_name        = "developer-log-reader"
  role_description = "ให้ทีม developer อ่าน log ของ my-app"

  # ── ใคร: IAM user ในบัญชีนี้ ที่ผ่าน MFA และมีสิทธิ์ assume ฝั่งตัวเอง
  assume_role_policy = data.aws_iam_policy_document.dev_assume.json

  # ── ได้อะไร: อ่าน log ของ my-app เท่านั้น
  inline_policies = {
    log-reader = data.aws_iam_policy_document.log_reader.json
  }

  max_session_duration = 3600

  tags = {
    Team   = "developer"
    Access = "read-only"
  }
}
```

**ยังไม่จบ** — account id ฝั่ง trust แปลว่า "ให้บัญชีนี้ไปตัดสินใจเอง" ต้องมีอีกครึ่งคือให้สิทธิ์ฝั่ง user ด้วย ส่วนนี้โมดูลยังไม่รองรับ (ไม่มี user/group) เลยต้องเขียนตรง ๆ

```hcl
resource "aws_iam_group" "developers" {
  name = "developers"
}

data "aws_iam_policy_document" "allow_assume" {
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [module.developer_log_reader.role_arn]
  }
}

resource "aws_iam_group_policy" "allow_assume" {
  name   = "assume-log-reader"
  group  = aws_iam_group.developers.name
  policy = data.aws_iam_policy_document.allow_assume.json
}

resource "aws_iam_user_group_membership" "alice" {
  user   = "alice"
  groups = [aws_iam_group.developers.name]
}
```

**สรุปสิทธิ์ที่ได้:**

| ทำอะไรได้ | กับ resource ไหน |
|---|---|
| อ่าน log event / ค้น Logs Insights | log group ที่ขึ้นต้นด้วย `/aws/lambda/my-app` เท่านั้น |
| ดึงผลลัพธ์ query | เฉพาะ query ที่ตัวเองเริ่ม |
| เขียน / ลบ log | **ไม่ได้** |
| log group ของทีมอื่น, CloudTrail, VPC Flow Logs | **ไม่ได้** |

**วิธีใช้ฝั่ง developer** — ใส่ใน `~/.aws/config`

```ini
[profile log-reader]
role_arn       = arn:aws:iam::123456789012:role/developer-log-reader
source_profile = default
mfa_serial     = arn:aws:iam::123456789012:mfa/alice
```

```bash
aws logs tail /aws/lambda/my-app --follow --profile log-reader
```

**กับดักของเคสนี้**

| กับดัก | รายละเอียด |
|---|---|
| ARN ต้องใส่ 2 บรรทัด | `logs:GetLogEvents` ทำงานที่ระดับ log *stream* ถ้าใส่แค่ ARN ของ log group จะได้ `AccessDenied` ทั้งที่ policy ดูเหมือนถูก |
| อย่าใช้ `CloudWatchLogsReadOnlyAccess` | เป็น managed policy ที่ให้ resource `*` = อ่านได้ทุก log group ในบัญชี รวม CloudTrail, VPC Flow Logs และ log ของทีมอื่น |
| read-only ≠ ไม่มีความเสี่ยง | ถ้า log มี PII หรือ token การให้ทีมอ่านคือการให้เห็นข้อมูล production ควรคุยเรื่อง log redaction ควบคู่ไปด้วย |
| ถ้าองค์กรใช้ IAM Identity Center (SSO) | อย่าสร้าง IAM user ใหม่ ให้ทำเป็น permission set แทน ซึ่งอยู่นอกขอบเขตโมดูลนี้ |

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
| `assume_role_policy` | trust policy JSON ดิบ **ทับ** สองตัวข้างบนเมื่อระบุ จำเป็นเมื่อต้องใช้ condition เช่น บังคับ MFA หรือ OIDC | `string` | `null` | no |

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
