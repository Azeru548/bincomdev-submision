variable "region" {
  description = "AWS region to deploy into. us-east-1 has all free-tier eligible sizes."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used as a prefix for every resource and tag."
  type        = string
  default     = "prestashop"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "project must be lowercase letters, digits and hyphens (3-21 chars)."
  }
}

variable "owner_tag" {
  description = "Value for the Owner tag, e.g. your name or student ID."
  type        = string
  default     = "student"
}

variable "instance_type" {
  description = <<-EOT
    Application server size. Free options:
      t4g.small  - AWS T4g free trial: 750 h/month for every account until 2026-12-31 (default).
      t3.micro   - 750 h/month only on legacy free-tier accounts (created before 2025-07-15).
      t4g.micro  - eligible on the credit-based Free Plan; billed from credits elsewhere.
  EOT
  type        = string
  default     = "t4g.small"
}

variable "db_instance_class" {
  description = "RDS size. db.t4g.micro (Free Plan) and db.t3.micro (legacy) are the free-eligible classes."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_admin_username" {
  description = "RDS master user. Cannot be a reserved word such as 'admin' or 'root'."
  type        = string
  default     = "psadmin"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form, allowed to SSH (port 22). Find it with: curl -s https://checkip.amazonaws.com"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block, e.g. 203.0.113.24/32."
  }
}

variable "shop_name" {
  description = "Store name shown in the PrestaShop front office."
  type        = string
  default     = "PrestaShop on AWS"
}

variable "admin_email" {
  description = "Email for the PrestaShop back-office administrator account."
  type        = string
  default     = "admin@example.com"
}

variable "admin_password" {
  description = "Back-office password. Change it after the first login; it is stored in EC2 user-data."
  type        = string
  default     = "PrestaShop2026!Demo"
  sensitive   = true
}

variable "admin_firstname" {
  description = "Back-office administrator first name."
  type        = string
  default     = "Store"
}

variable "admin_lastname" {
  description = "Back-office administrator last name."
  type        = string
  default     = "Admin"
}

variable "ps_version" {
  description = "PrestaShop release to install. The 8.2 line is the LTS line that supports PHP 8.1."
  type        = string
  default     = "8.2.9"

  validation {
    condition     = can(regex("^8\\.2\\.[0-9]+$", var.ps_version))
    error_message = "ps_version must be a PrestaShop 8.2.x release: 8.2.x refuses to install on PHP newer than 8.1."
  }
}
