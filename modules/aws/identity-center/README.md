# AWS IAM Identity Center Module

จัดการ **ใครเข้าบัญชีไหนได้ ด้วยสิทธิ์อะไร** ในองค์กรที่มีหลาย AWS account

## ต่างจากโมดูล `iam` ยังไง

| | [`../iam`](../iam) (IAM role) | โมดูลนี้ (Identity Center) |
|---|---|---|
| ใช้กับ | **service** เช่น EC2, Lambda | **คน** เช่น developer, ops |
| ตัวตนอยู่ที่ไหน | IAM ในบัญชีนั้น ๆ | identity store กลาง (หรือ sync มาจาก Entra ID / Okta / Google) |
| ขอบเขต | ทีละบัญชี | ครอบทุกบัญชีใน organization |
| การเข้าถึง | assume role ผ่าน STS | login ผ่าน AWS access portal |
| credential | ต้องมี long-lived key หรือ profile | ไม่มี key ถาวรเลย หมดอายุตาม session |

> [!NOTE]
> IAM user ไม่ควรถูกสร้างเพิ่มถ้าองค์กรใช้ Identity Center แล้ว — ให้ทุกคนเข้าผ่าน portal แทน (ตรงกับที่ระบุไว้ท้ายตาราง "กับดัก" ในโมดูล `iam`)

## เริ่มจากตรงนี้ก่อน: 1 การให้สิทธิ์ = 3 คำตอบ

ทุกอย่างในโมดูลนี้ประกอบขึ้นจากคำถาม 3 ข้อ ที่ **จับคู่กันเป็น account assignment**

```
   คำถาม 1: ใคร              คำถาม 2: ทำอะไรได้           คำถาม 3: ที่บัญชีไหน
   ┌──────────────┐          ┌──────────────────┐         ┌──────────────────┐
   │ Group        │          │ Permission set   │         │ AWS account      │
   │ platform-team│          │ AdminAccess      │         │ 111122223333     │
   │ (alice, bob) │          │ PT1H             │         │ 444455556666     │
   └──────┬───────┘          └────────┬─────────┘         └────────┬─────────┘
          │                           │                            │
          └───────────────────────────┴────────────────────────────┘
                                      │
                                      ▼
                            account assignment
                                      │
                     ตอน login AWS สร้าง IAM role ให้อัตโนมัติ
                     ในบัญชีปลายทาง ชื่อ AWSReservedSSO_AdminAccess_xxxx
```

| | คำถาม | ศัพท์ AWS | ตัวแปรในโมดูลนี้ |
|:--:|---|---|---|
| **1** | **ใคร** | user / group ใน identity store | `users`, `groups` |
| **2** | **ทำอะไรได้** | permission set | `permission_sets` |
| **3** | **ที่บัญชีไหน** | account assignment | `assignments` |

> [!IMPORTANT]
> **permission set ที่ยังไม่ถูก assign ไม่มีผลอะไรเลย** — มันเป็นแค่ "แม่แบบสิทธิ์" ที่ลอยอยู่เฉย ๆ
> สิทธิ์จะเกิดขึ้นจริงต่อเมื่อมี assignment ที่จับ principal + permission set + account เข้าด้วยกัน

## ข้อกำหนดก่อนใช้

| เงื่อนไข | รายละเอียด |
|---|---|
| ต้องเปิด Identity Center ไว้ก่อน | เปิดจาก console ครั้งเดียว โมดูลนี้ไม่ได้เปิดให้ (ไม่มี API สำหรับสร้าง instance) |
| ต้อง apply จากบัญชีที่ถูกต้อง | management account ของ organization หรือบัญชีที่ถูกตั้งเป็น delegated administrator |
| region ต้องตรง | Identity Center อยู่ได้ region เดียว provider ต้องชี้ไป region นั้น |

โมดูลค้นหา instance ให้เองผ่าน `aws_ssoadmin_instances` ถ้ายังไม่ได้เปิดใช้งาน `terraform plan` จะเตือนด้วยข้อความจาก `check` block

## ถ้า sync ผู้ใช้มาจาก IdP อยู่แล้ว (SCIM)

องค์กรส่วนใหญ่ต่อ Entra ID / Okta / Google Workspace เข้ากับ Identity Center ผ่าน SCIM ในกรณีนั้น **identity store เป็น read-only** สร้าง user/group ผ่าน Terraform ไม่ได้

โมดูลรองรับเคสนี้อยู่แล้ว: ชื่อที่อ้างใน `assignments` แต่ไม่ได้ประกาศใน `users`/`groups` จะถูก **ค้นหา** ในระบบแทนที่จะถูกสร้าง

```hcl
module "sso" {
  source = "../../modules/aws/identity-center"

  # ไม่ประกาศ users/groups เลย เพราะ sync มาจาก Okta

  permission_sets = {
    ReadOnlyAccess = {
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }

  assignments = {
    devs = {
      permission_set = "ReadOnlyAccess"
      groups         = ["okta-developers"]   # ← หาให้ ไม่ได้สร้างใหม่
      account_ids    = ["111122223333"]
    }
  }
}
```

ถ้าชื่อไม่ตรงกับที่มีอยู่จริง `terraform plan` จะล้มเหลวตอน lookup ซึ่งเป็นพฤติกรรมที่ต้องการ — ดีกว่าไปสร้าง group ซ้ำเงียบ ๆ

## Usage

### 1. เคสพื้นฐาน — admin กับ read-only

```hcl
module "sso" {
  source = "../../modules/aws/identity-center"

  # ── ใคร
  users = {
    alice = { given_name = "Alice", family_name = "Ng", email = "alice@example.com" }
    bob   = { given_name = "Bob", family_name = "Lee", email = "bob@example.com" }
  }

  groups = {
    platform-team = {
      description = "ทีมที่ดูแล infrastructure"
      members     = ["alice", "bob"]
    }
  }

  # ── ทำอะไรได้
  permission_sets = {
    AdministratorAccess = {
      description         = "สิทธิ์เต็มสำหรับทีม platform"
      session_duration    = "PT1H"                 # session สั้น เพราะสิทธิ์แรง
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    ReadOnlyAccess = {
      session_duration    = "PT8H"                 # อ่านอย่างเดียว ให้ยาวได้ทั้งวันทำงาน
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }

  # ── ที่บัญชีไหน
  assignments = {
    platform-admin = {
      permission_set = "AdministratorAccess"
      groups         = ["platform-team"]
      account_ids    = ["111122223333"]                    # เฉพาะ prod
    }

    platform-readonly = {
      permission_set = "ReadOnlyAccess"
      groups         = ["platform-team"]
      account_ids    = ["111122223333", "444455556666"]    # ทั้ง prod และ dev
    }
  }

  tags = { ManagedBy = "terraform" }
}
```

**สรุปสิทธิ์ที่ได้:**

| ใคร | บัญชี 111122223333 (prod) | บัญชี 444455556666 (dev) |
|---|---|---|
| alice, bob | Admin (1 ชม.) และ ReadOnly (8 ชม.) | ReadOnly (8 ชม.) |
| คนอื่น | **ไม่ได้** | **ไม่ได้** |

### 2. permission set ที่จำกัดถึง resource ตัวเดียว

`managed_policy_arns` คุมขอบเขต resource ไม่ได้ ถ้าต้องจำกัดถึง bucket ตัวใดตัวหนึ่ง ให้ใช้ `inline_policy` — หลักการเดียวกับ `inline_policies` ในโมดูล [`../iam`](../iam)

```hcl
data "aws_iam_policy_document" "support" {
  statement {
    sid       = "ReadAppData"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::my-app-data/*"]
  }

  statement {
    sid       = "ReadLogs"
    effect    = "Allow"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/my-app*:log-stream:*"]
  }
}

module "sso" {
  source = "../../modules/aws/identity-center"

  permission_sets = {
    AppSupport = {
      description      = "ทีม support ดูข้อมูลแอปได้อย่างเดียว"
      session_duration = "PT4H"
      inline_policy    = data.aws_iam_policy_document.support.json
    }
  }

  assignments = {
    support = {
      permission_set = "AppSupport"
      groups         = ["support-team"]
      account_ids    = ["111122223333"]
    }
  }
}
```

### 3. เพดานสิทธิ์ (permissions boundary)

ให้ทีมทำอะไรก็ได้ **ยกเว้น** เกินเพดาน ใช้ตอนอยากมอบสิทธิ์กว้าง ๆ แต่กัน blast radius

```hcl
permission_sets = {
  Developer = {
    managed_policy_arns  = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    permissions_boundary = {
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    }
  }
}
```

สิทธิ์จริง = policy ที่แนบ ∩ boundary

ถ้าใช้ policy ที่เขียนเอง ต้องเป็น **customer managed policy ที่มีอยู่แล้วในทุกบัญชีปลายทาง** ภายใต้ชื่อและ path เดียวกัน (AWS ไม่ copy ให้)

```hcl
permission_sets = {
  Developer = {
    managed_policy_arns       = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    customer_managed_policies = [{ name = "team-guardrails", path = "/" }]
    permissions_boundary = {
      customer_managed_policy_reference = { name = "org-boundary" }
    }
  }
}
```

### 4. ABAC — ให้สิทธิ์ตาม attribute แทนการไล่ assign ทีละบัญชี

ส่ง attribute จาก identity store เข้าไปเป็น session tag แล้วให้ policy ตัดสินจาก tag นั้น

```hcl
module "sso" {
  source = "../../modules/aws/identity-center"

  access_control_attributes = {
    Team = ["$${path:enterprise.department}"]
    Env  = ["$${path:enterprise.division}"]
  }
}
```

จากนั้นเขียน condition ใน `inline_policy` ให้ resource ที่มี tag `Team` ตรงกับของผู้ใช้เท่านั้นที่แตะได้

```hcl
condition {
  test     = "StringEquals"
  variable = "aws:ResourceTag/Team"
  values   = ["$${aws:PrincipalTag/Team}"]
}
```

## วิธีเข้าใช้งานฝั่งผู้ใช้

```bash
aws configure sso
# SSO start URL: https://d-xxxxxxxxxx.awsapps.com/start
# แล้วเลือก account + permission set ที่ตัวเองได้รับสิทธิ์
```

```bash
aws sso login --profile prod-admin
aws s3 ls --profile prod-admin
```

## กับดักที่เจอบ่อย

| กับดัก | รายละเอียด |
|---|---|
| ชื่อ permission set ยาวเกิน | AWS จำกัด 32 ตัวอักษร โมดูลตรวจให้ตั้งแต่ `plan` |
| แก้ policy แล้วสิทธิ์ไม่เปลี่ยน | AWS ต้อง re-provision permission set ไปยังทุกบัญชี provider ทำให้อัตโนมัติ แต่ไม่ใช่ทันที และ session ที่เปิดค้างอยู่ยังใช้สิทธิ์เดิมจนหมดอายุ |
| assign เยอะแล้วโดน throttle | SSO Admin API rate limit ค่อนข้างต่ำ ถ้ามีหลายร้อย assignment ควรลด `-parallelism` |
| customer managed policy ไม่มีในบัญชีปลายทาง | assignment จะล้มเหลว ต้องสร้าง policy ชื่อ/path เดียวกันไว้ทุกบัญชีก่อน |
| ลบ permission set ที่ยังมี assignment | Terraform จัดลำดับให้ถูกเอง แต่ถ้าไปแก้ผ่าน console ปนกันจะเกิด state drift |
| แก้ `users`/`groups` ทั้งที่ต่อ SCIM อยู่ | identity store เป็น read-only จะได้ error ตอน apply ให้ปล่อยว่างแล้วอ้างชื่อจาก IdP แทน |
| เปลี่ยน key ใน `assignments` | ไม่มีผล เพราะโมดูลคีย์ตามตัวสิทธิ์จริง (`account|permission_set|principal`) ไม่ใช่ชื่อ label |

## ตรวจสอบหลัง apply

ดูว่าใครได้สิทธิ์อะไรบ้าง:

```bash
terraform output -json account_assignments | jq 'keys'
```

ดู IAM role ที่ AWS สร้างให้ในบัญชีปลายทาง:

```bash
aws iam list-roles --query "Roles[?starts_with(RoleName, 'AWSReservedSSO_')].RoleName"
```

## Inputs

**ตอบคำถามข้อ 1 — ใคร**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `users` | user ที่จะสร้างใน identity store คีย์คือ user name **ปล่อยว่างถ้า sync ผ่าน SCIM** | `map(object)` | `{}` | no |
| `groups` | group ที่จะสร้าง คีย์คือ display name `members` คือ user name (จะเป็น user ในโมดูลหรือที่มีอยู่แล้วก็ได้) | `map(object)` | `{}` | no |

**ตอบคำถามข้อ 2 — ทำอะไรได้**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `permission_sets` | permission set ที่จะสร้าง คีย์คือชื่อ (≤ 32 ตัวอักษร) | `map(object)` | `{}` | no |

โครงของแต่ละ permission set:

| Field | Description | Type | Default |
|---|---|---|---|
| `description` | คำอธิบาย | `string` | `null` |
| `session_duration` | อายุ session แบบ ISO-8601 รวมแล้วต้องอยู่ระหว่าง 1 นาที ถึง 12 ชั่วโมง | `string` | `"PT1H"` |
| `relay_state` | URL ที่ให้เด้งไปหลัง login เช่นหน้า console ของ service ใด service หนึ่ง | `string` | `null` |
| `managed_policy_arns` | ARN ของ AWS managed policy ขอบเขต resource คุมไม่ได้ | `list(string)` | `[]` |
| `customer_managed_policies` | policy ที่ต้องมีอยู่แล้ว**ในทุกบัญชีปลายทาง** ระบุ `name` และ `path` | `list(object)` | `[]` |
| `inline_policy` | policy JSON ที่ฝังใน permission set ใช้เมื่อต้องระบุ resource ARN เอง | `string` | `null` |
| `permissions_boundary` | เพดานสิทธิ์ ใส่ได้อย่างใดอย่างหนึ่งระหว่าง `managed_policy_arn` กับ `customer_managed_policy_reference` | `object` | `null` |
| `tags` | tag เฉพาะ permission set นี้ | `map(string)` | `{}` |

**ตอบคำถามข้อ 3 — ที่บัญชีไหน**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `assignments` | การให้สิทธิ์ คีย์เป็น label ที่ตั้งเองและ**ไม่ถูกส่งไป AWS** | `map(object)` | `{}` | no |

โครงของแต่ละ assignment:

| Field | Description | Type | Default |
|---|---|---|---|
| `permission_set` | ชื่อ permission set ต้องมีอยู่ใน `permission_sets` | `string` | – |
| `groups` | display name ของ group ที่ได้รับสิทธิ์ | `list(string)` | `[]` |
| `users` | user name ที่ได้รับสิทธิ์ (แนะนำให้ใช้ group แทน) | `list(string)` | `[]` |
| `account_ids` | AWS account ID 12 หลักที่ให้สิทธิ์ | `list(string)` | – |

**อื่น ๆ**

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `instance_arn` | ARN ของ Identity Center instance ค้นหาให้เองถ้าไม่ระบุ | `string` | `null` | no |
| `identity_store_id` | ID ของ identity store ค้นหาให้เองถ้าไม่ระบุ | `string` | `null` | no |
| `access_control_attributes` | attribute สำหรับ ABAC map ของ ชื่อ attribute → source path | `map(list(string))` | `{}` | no |
| `tags` | tag ที่ใส่ให้ทุก permission set ในโมดูล | `map(string)` | `{}` | no |

## Outputs

| Name | Description | ใช้ตอนไหน |
|------|-------------|-----------|
| `permission_set_arns` | map ของ ชื่อ → ARN | อ้างถึง permission set จากนอกโมดูล |
| `permission_set_ids` | map ของ ชื่อ → `ps-xxxx` | หาให้ตรงกับที่เห็นใน console |
| `group_ids` | map ของ display name → group ID (รวมทั้งที่สร้างและที่มีอยู่แล้ว) | อ้างใน resource อื่น |
| `user_ids` | map ของ user name → user ID (รวมทั้งที่สร้างและที่มีอยู่แล้ว) | อ้างใน resource อื่น |
| `account_assignments` | สิทธิ์ที่เกิดขึ้นจริงทั้งหมด | ตรวจสอบว่าใครได้อะไรที่บัญชีไหน |
| `group_membership_ids` | map ของ `group/user` → membership ID | ตรวจสอบสมาชิกกลุ่ม |
| `instance_arn` | ARN ของ instance ที่ใช้อยู่ | ส่งต่อให้โมดูลอื่น |
| `identity_store_id` | ID ของ identity store | ส่งต่อให้โมดูลอื่น |

## Requirements

| Name | Version |
|------|---------|
| terraform | `>= 1.11.0` |
| aws provider | `>= 5.0` |
