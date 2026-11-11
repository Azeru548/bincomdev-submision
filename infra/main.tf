###############################################################################
# PrestaShop on AWS - application server and database on separate hosts.
#
#   Internet -> IGW -> public subnet (EC2 + Elastic IP, Nginx/PHP-FPM)
#                              |
#                              +-- TCP/3306 --> private subnet (RDS MySQL 8.0)
#
# The database has no route to the internet and accepts traffic only from the
# application server's security group.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  # Ubuntu 22.04 ships PHP 8.1, the newest PHP that PrestaShop 8.2.9 accepts.
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  public_cidrs = [for i in range(2) : cidrsubnet("10.20.0.0/16", 8, 10 + i)]
  db_cidrs     = [for i in range(2) : cidrsubnet("10.20.0.0/16", 8, 20 + i)]
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${local.azs[count.index]}", Tier = "web" }
}

resource "aws_subnet" "db" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.db_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.project}-db-${local.azs[count.index]}", Tier = "database" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table with no default route: the database cannot reach or be reached
# from the internet. RDS does not need egress to serve queries.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project}-db-rt" }
}

resource "aws_route_table_association" "db" {
  count = 2

  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "PrestaShop web server: HTTP(S) from anywhere, SSH from the admin IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP (public storefront URL)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (enabled later with a domain + certificate)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from the operator's public IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Outgoing: apt packages, PrestaShop download, MySQL to RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db-sg"
  description = "MySQL reachable only from the PrestaShop application security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from the application server only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-db-sg" }
}

# ---------------------------------------------------------------------------
# Database tier (RDS MySQL 8.0, separate host from the web server)
# ---------------------------------------------------------------------------

resource "random_password" "db_admin" {
  length           = 24
  special          = true
  override_special = "-_.~"
}

resource "random_password" "db_app" {
  length           = 24
  special          = true
  override_special = "-_.~"
}

resource "aws_db_subnet_group" "app" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.db[*].id

  tags = { Name = "${var.project}-db-subnets" }
}

resource "aws_db_instance" "app" {
  identifier = "${var.project}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  # Free-tier shape: single-AZ, 20 GB gp2, short backup retention.
  allocated_storage       = 20
  storage_type            = "gp2"
  storage_encrypted       = true
  multi_az                = false
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  db_name  = "prestashop"
  username = var.db_admin_username
  password = random_password.db_admin.result
  port     = 3306

  # Not reachable from the internet: private subnets + SG restricted to the app SG.
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.app.name

  auto_minor_version_upgrade   = true
  apply_immediately            = true
  performance_insights_enabled = false
  skip_final_snapshot          = true # assignment instance: lets `terraform destroy` clean up
  deletion_protection          = false

  tags = { Name = "${var.project}-mysql" }
}

# ---------------------------------------------------------------------------
# SSH key pair (generated so the stack is turnkey; private key written locally)
# ---------------------------------------------------------------------------

resource "tls_private_key" "app" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "app" {
  key_name   = "${var.project}-key"
  public_key = tls_private_key.app.public_key_openssh

  tags = { Name = "${var.project}-key" }
}

resource "local_sensitive_file" "key" {
  filename        = "${path.module}/${var.project}-key.pem"
  content         = tls_private_key.app.private_key_pem
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# Application tier (EC2 + Elastic IP)
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.app.key_name
  associate_public_ip_address = true

  # IMDSv2 only: blocks SSRF-style credential theft from the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 20 # free tier includes 30 GB of EBS
    volume_type = "gp3"
    encrypted   = true
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-app" }

  # The bootstrap connects to MySQL, so let RDS finish first.
  depends_on = [aws_db_instance.app]

  lifecycle {
    # EC2 rejects user-data larger than 16 KiB. The installer is gzipped into the
    # bootstrap; this guard fails the plan instead of a half-booted instance.
    precondition {
      condition     = length(local.user_data) <= 16384
      error_message = "Rendered user_data exceeds EC2's 16 KiB limit - shorten scripts/install-prestashop.sh."
    }
  }
}

resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "${var.project}-eip" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

# ---------------------------------------------------------------------------
# Bootstrap: drop credentials on the box, then run the installer script
# ---------------------------------------------------------------------------

locals {
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail

    install -d -m 0750 /etc/prestashop
    umask 077
    cat > /etc/prestashop/app.env <<'APPENV'
    DB_HOST="${aws_db_instance.app.address}"
    DB_PORT="3306"
    DB_NAME="prestashop"
    DB_ADMIN_USER="${var.db_admin_username}"
    DB_ADMIN_PASSWORD="${random_password.db_admin.result}"
    DB_APP_USER="ps_app"
    DB_APP_PASSWORD="${random_password.db_app.result}"
    SHOP_NAME="${var.shop_name}"
    SHOP_EMAIL="${var.admin_email}"
    ADMIN_EMAIL="${var.admin_email}"
    ADMIN_PASSWORD="${var.admin_password}"
    ADMIN_FIRSTNAME="${var.admin_firstname}"
    ADMIN_LASTNAME="${var.admin_lastname}"
    TIMEZONE="UTC"
    COUNTRY="us"
    LANGUAGE="en"
    PS_VERSION="${var.ps_version}"
    APPENV
    chmod 0600 /etc/prestashop/app.env

    echo '${base64gzip(file("${path.module}/../scripts/install-prestashop.sh"))}' | base64 -d | gunzip > /usr/local/sbin/install-prestashop.sh
    chmod 0755 /usr/local/sbin/install-prestashop.sh
    /usr/local/sbin/install-prestashop.sh
  EOT
}
