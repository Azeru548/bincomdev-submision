# PrestaShop on AWS — Implementation Runbook

Self-hosted PrestaShop 8.2.9 on an AWS EC2 application server with its MySQL 8.0
database on a **separate Amazon RDS host**, sized inside the AWS Free Tier.

> **Read this first.** This document, the Terraform stack and the installer are
> complete and locally validated, but **the deployment itself has not been run**:
> the machine that produced these files has no AWS account, no credentials and no
> access to your AWS Console. There is therefore **no live URL in this document**
> and **no AWS Console screenshots** — those can only be produced by the account
> owner. Section 10 is a screenshot checklist that tells you exactly what to
> capture at each step, and where this runbook says *"capture"* that is the
> moment to take it. Everything up to and including the commands is done for you.

---

## 1. Solution overview

```
                    Internet (student / grader)
                              |
                              |  HTTP :80
                              v
                 +----------------------------+
                 |  Elastic IP (static)        |
                 |  ec2-<ip>.compute-1.amazonaws.com
                 +-------------+--------------+
                               |
   VPC 10.20.0/16              v
   +---------------------------------------------------------------+
   |  public subnet 10.20.10.0/24 (us-east-1a)                     |
   |    EC2  prestashop-app   t4g.small, Ubuntu 22.04 arm64        |
   |    Nginx + PHP 8.1-FPM + PrestaShop 8.2.9                     |
   |    SG prestashop-app-sg: 80/443 world, 22 admin IP only        |
   +-----------------------------+---------------------------------+
                                 |  TCP 3306 (SG-to-SG reference only)
                                 v
   |  private subnet 10.20.20.0/24 (us-east-1a)                    |
   |    RDS  prestashop-mysql  db.t4g.micro, MySQL 8.0             |
   |    SG prestashop-db-sg: 3306 from the app SG, no internet      |
   |    route table: no 0.0.0.0/0 route (no NAT, no egress)         |
   +---------------------------------------------------------------+
```

Two independently provisioned compute hosts, two security groups, a
security-group-to-security-group rule, and a database with no route to the
internet. That is the "database must not be hosted on the application server"
requirement, enforced by the network rather than by convention.

---

## 2. Requirement → evidence map

| Requirement | How it is met | Evidence to submit |
|---|---|---|
| New server instance, PrestaShop installed | EC2 `prestashop-app`, PrestaShop 8.2.9 installed by `scripts/install-prestashop.sh` | EC2 console screenshot + storefront screenshot |
| Publicly accessible URL, provider default | Elastic IP whose default AWS DNS name `ec2-<ip>.<region>.compute-1.amazonaws.com` serves the store on port 80 | Browser screenshot with URL bar visible |
| URL submitted | `terraform output store_url` | URL in the report |
| Step-by-step documentation | This runbook (section 5 automated, section 6 manual console) | The report itself |
| Screenshots of AWS Console + configuration decisions | Section 10 checklist, section 7 decision log | 16 annotated screenshots |
| Database not on the application server | Amazon RDS MySQL 8.0 in a private subnet; app connects to a remote endpoint | RDS console screenshot + `ss -ltnp \| grep 3306` returning nothing on EC2 |
| AWS Free Tier only | Free-eligible instance classes and 20 GB volumes; budget alarm; no NAT gateway, no ALB, no Multi-AZ | Billing/Cost Explorer screenshot, section 8 |

---

## 3. Free-tier sizing — read this before you click

AWS has two free-tier regimes, and the difference decides which instance types
are free for you:

| | Legacy free tier (account created **before 15 Jul 2025**) | Current Free Plan (accounts created after) |
|---|---|---|
| EC2 | 750 h/month of `t2.micro` / `t3.micro` for 12 months | $100 credit + up to $100 more for setup activities; EC2 draws on the credits, Free Plan expires after 6 months |
| RDS | 750 h/month of single-AZ `db.t3.micro` / `db.t4g.micro` + 20 GB, 12 months | Same instances are Free-Plan eligible, but usage draws on credits |
| T4g trial | `t4g.small` 750 h/month free for **all** account types **until 31 Dec 2026** | Same |

Defaults in this stack: **`t4g.small`** (T4g trial, free through 2026-12-31 on any
account) and **`db.t4g.micro`**. If your account is on the legacy free tier and
you want the 12-month RDS/EC2 allowance instead, set
`instance_type = "t3.micro"` in `terraform.tfvars` — but note that `t3.micro`
needs an amd64 AMI, so also change the AMI filter's `architecture` to `x86_64`
and `name` suffix `amd64`, or pick the amd64 image in the console.

What keeps this inside the allowance:

* 20 GB gp3 root volume and 20 GB gp2 database storage (allowance is 30 GB EBS + 20 GB RDS).
* Single-AZ RDS, no read replica, no Multi-AZ, 1-day backup retention.
* No NAT gateway (~$32/month), no Application Load Balancer (~$16/month), no Route 53 hosted zone.
* No CloudWatch dashboards, no Performance Insights, no Secrets Manager.
* One Elastic IP attached to a running instance (free while attached).

Set a **$1 budget alarm** on day one; section 8 has the exact steps.

---

## 4. Prerequisites

1. AWS account with a payment method (required for identity verification even on the Free Plan).
2. AWS CLI v2 and Terraform ≥ 1.5, **or** just console access if you follow section 6 by hand.
3. Your public IP: open the checkip service page in a browser, or read the IP hint
   in the AWS console, and use the address shown as `<your-ip>/32`.
4. Nothing else — the SSH key pair is generated by Terraform, and PrestaShop is
   downloaded from its official GitHub release page on the instance.

---

## 5. Path A — automated deployment (recommended, ~20 minutes)

> **No local tooling?** Use [cloudshell-deploy.md](cloudshell-deploy.md) instead:
> it provisions this exact stack from AWS CloudShell with a single script
> (`scripts/deploy-aws-cli.sh`), which needs no Terraform and no AWS keys outside
> your own console session. Everything below applies either way.

From the project root:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_cidr to your IP/32, owner_tag, admin_email
terraform init
terraform plan   -out tfplan     # optional: screenshot the resource list as an extra exhibit
terraform apply  tfplan          # ~10-15 min, RDS is created first
```

What `apply` creates, in order: VPC, IGW, 2 public + 2 private subnets across two
AZs, route tables, two security groups, the RDS subnet group, the MySQL 8.0
instance, the SSH key pair (+ `prestashop-key.pem` written locally), the EC2
instance, the Elastic IP and its association. The instance's user-data writes
`/etc/prestashop/app.env` (credentials, 0600) and runs the installer.

Then:

```bash
terraform output store_url            # http://ec2-x-x-x-x.compute-1.amazonaws.com/
terraform output -raw next_steps
ssh -i prestashop-key.pem ubuntu@$(terraform output -raw public_ip) \
    'sudo tail -f /var/log/prestashop-install.log'     # watch bootstrap
ssh -i prestashop-key.pem ubuntu@$(terraform output -raw public_ip) \
    'sudo cat /root/prestashop-summary.txt'            # admin URL + credentials
```

Bootstrap takes 6–10 minutes after the instance is running (apt, ~80 MB download,
database schema import, demo fixtures). When the log ends with
`Done. Summary written to /root/prestashop-summary.txt`, open the store URL.

Then verify from your laptop:

```bash
./scripts/verify-deployment.sh "$(cd infra && terraform output -raw store_url)"
```

---

## 6. Path B — manual AWS Console (use this for the click-through screenshots)

You can do Path A and still capture these screens; the resource names match.
Region: **us-east-1**.

### 6.1 VPC and subnets

1. VPC → **Create VPC** → *VPC and more*: name `prestashop-vpc`, IPv4 `10.20.0.0/16`,
   2 AZs, 2 public subnets, **2 private subnets**, NAT gateway = **None**
   (RDS needs no internet egress; this avoids the ~$32/month NAT charge).
2. Confirm the private route table has **no** `0.0.0.0/0` route.

**S1** — VPC resource map: name, CIDR, 2 public + 2 private subnets, NAT gateway *None*.

### 6.2 Security groups

3. EC2 → Security Groups → create `prestashop-app-sg` in the VPC:
   * HTTP 80 from `0.0.0.0/0`
   * HTTPS 443 from `0.0.0.0/0`
   * SSH 22 from `<your-ip>/32` — *not* `0.0.0.0/0`
4. Create `prestashop-db-sg`: MySQL/Aurora **3306**, source = **the app security group ID**
   (type the SG id, not a CIDR). No other inbound rules.

**S2** — `prestashop-db-sg` inbound rules: 3306, source = `sg-... (prestashop-app-sg)`, no CIDR.

### 6.3 Database (separate host)

5. RDS → **Create database** → *Standard create* → **MySQL 8.0** → template **Free tier**.
   * DB instance identifier `prestashop-mysql`
   * Master username `psadmin`, **self-managed** credentials (24+ chars)
   * Instance class `db.t4g.micro`, storage **20 GiB gp2**, *disable* storage autoscaling
   * **Multi-AZ: No**; **Public access: No**
   * VPC `prestashop-vpc`, subnet group covering the **two private subnets**,
     security group `prestashop-db-sg`
   * Initial database name `prestashop`, backup retention 1 day, encryption on,
     Performance Insights off, deletion protection off
6. Wait for status **Available**, then copy the **Endpoint** (e.g.
   `prestashop-mysql.abc123xyz.us-east-1.rds.amazonaws.com:3306`).

**S3** — RDS instance summary: engine MySQL 8.0, class `db.t4g.micro`, status Available, **Publicly accessible: No**.
**S4** — RDS *Connectivity & security*: endpoint + port, VPC, subnet group, SG.

### 6.4 Application server

7. EC2 → **Launch instance**:
   * Name `prestashop-app`, AMI **Ubuntu Server 22.04 LTS (arm64)**
   * Instance type `t4g.small`, key pair *Create new key pair* → download `.pem`
   * Network `prestashop-vpc`, **public** subnet, **Auto-assign public IP: Enable**
   * Security group `prestashop-app-sg`
   * Storage: **20 GiB gp3**, encrypted
   * Advanced → Metadata: **IMDSv2 required**
8. Allocate an **Elastic IP** and associate it with the instance (stable URL).

**S5** — EC2 instance list: state Running, instance type, public IPv4/DNS, AZ, security group.
**S6** — Instance details → *Storage*: 20 GiB gp3 root volume only (no local database volume).
**S7** — Elastic IP associated with `prestashop-app`.

### 6.5 Install the stack

9. SSH in:
   ```bash
   chmod 600 prestashop-key.pem
   ssh -i prestashop-key.pem ubuntu@<elastic-ip>
   ```
10. Create the configuration file, filling in the **RDS endpoint** and passwords:
    ```bash
    sudo install -d -m 0750 /etc/prestashop
    sudo tee /etc/prestashop/app.env >/dev/null <<'ENV'
    DB_HOST="prestashop-mysql.abc123xyz.us-east-1.rds.amazonaws.com"
    DB_PORT="3306"
    DB_NAME="prestashop"
    DB_ADMIN_USER="psadmin"
    DB_ADMIN_PASSWORD="CHANGE-ME"
    DB_APP_USER="ps_app"
    DB_APP_PASSWORD="CHANGE-ME-TOO"
    SHOP_NAME="PrestaShop on AWS"
    SHOP_EMAIL="admin@example.com"
    ADMIN_EMAIL="admin@example.com"
    ADMIN_PASSWORD="CHANGE-ME-AS-WELL"
    ADMIN_FIRSTNAME="Store"
    ADMIN_LASTNAME="Admin"
    TIMEZONE="UTC"
    COUNTRY="us"
    LANGUAGE="en"
    PS_VERSION="8.2.9"
    ENV
    sudo chmod 600 /etc/prestashop/app.env
    ```
11. Copy `scripts/install-prestashop.sh` to the instance (or paste it via
    `nano`) and run:
    ```bash
    sudo install -m 0755 install-prestashop.sh /usr/local/sbin/
    sudo /usr/local/sbin/install-prestashop.sh
    ```
    The script is idempotent and safe to re-run. It performs, in order: apt
    packages (Nginx, PHP 8.1-FPM + 11 extensions, MySQL client) → PHP limits
    (`memory_limit=512M`, `upload_max_filesize=32M`, `max_input_vars=5000`) →
    wait for RDS, create `prestashop` database + `ps_app` user with grants
    **on the remote host** → Nginx vhost → download PrestaShop 8.2.9 → unpack
    the wrapper zip → permissions → CLI install → move `/install` out of the
    web root → health check.
12. Read the summary: `sudo cat /root/prestashop-summary.txt`.

**S8** — SSH session running the installer / `tail` of `/var/log/prestashop-install.log` showing `-- Installation successful! --`.
**S9** — `sudo cat /root/prestashop-summary.txt` (blur the passwords).

### 6.6 PrestaShop back office

13. Open `http://<elastic-ip-dns>/adminXXXXX/`, sign in with the admin email and
    password, then **Advanced Parameters → Performance** and enable *Friendly URL*
    (the Nginx vhost already supports it), and change the admin password.
14. Add a product and a category so the storefront does not look empty.

**S10** — Back-office dashboard with the shop name in the header and the URL bar visible.
**S11** — Storefront home page with URL bar visible (the submitted URL).

---

## 7. Why these choices (decision log)

| # | Decision | Rationale / alternative rejected |
|---|---|---|
| 1 | **Two hosts: EC2 + RDS** | Explicit requirement. RDS also gives managed backups, patching and point-in-time recovery; the app host holds no data that cannot be rebuilt. |
| 2 | **RDS in a private subnet, no NAT** | Database is unreachable from the internet and has no egress; the only inbound path is the app SG. A NAT gateway would add ~$32/month for zero benefit here. |
| 3 | **SG-to-SG rule instead of source CIDR** | The rule survives app-server rebuilds and does not depend on the VPC's IP plan. |
| 4 | **Ubuntu 22.04 LTS, not 24.04** | PrestaShop 8.2.9's installer hard-caps PHP at 8.1 (`_PS_INSTALL_MAXIMUM_PHP_VERSION_ID_ = 81099`); 24.04 ships PHP 8.3 and is rejected. Verified by reading `install/install_version.php` in the release. |
| 5 | **PrestaShop 8.2.9 (LTS line), not 9.x** | 8.2 is the long-support branch with the widest module/theme compatibility and officially supports PHP 8.1. 9.x is newer but moves the PHP floor/ceiling and module compatibility. |
| 6 | **Nginx + PHP-FPM, not Apache + mod_php** | Lower memory footprint on a 2 GiB instance; PHP-FPM pools separate web and app lifecycles. Config ships with `try_files` rewrite rules and denies `/app`, `/config`, `/var`, `/vendor`, `/install`. |
| 7 | **CLI installer (`install/index_cli.php`)** | Reproducible, scriptable, no browser timeouts; the release package is a **wrapper zip containing `prestashop.zip`**, which the script unwraps — a step most tutorials miss. |
| 8 | **`/install` moved outside the web root** | Leaving it exposed lets anyone reinstall the shop. It is retained under `/var/lib/prestashop/` for a retry instead of deleted. |
| 9 | **Elastic IP + default AWS DNS name** | The requirement allows the provider's default URL; an EIP keeps that URL stable across stop/start. No custom domain or Route 53 zone (cost). |
| 10 | **Shop domain read from IMDSv2 at boot** | `--domain` must match the address users type, otherwise links and back-office redirects point at `localhost`. `--rewrite=0` initially avoids 404s until friendly URLs are proven. |
| 11 | **Dedicated `ps_app` MySQL user, least privilege** | PrestaShop never uses the RDS master account; the app user is granted only on `prestashop.*`. |
| 12 | **IMDSv2 required, SSH limited to one /32** | Blocks metadata credential theft via SSRF and keeps port 22 off the public scan surface. |
| 13 | **`t4g.small` + `db.t4g.micro`** | T4g trial covers the app host free through 2026-12-31 on every account type; the DB class is the free-eligible Graviton micro. See section 3 for legacy-account alternatives. |
| 14 | **Credentials in `/etc/prestashop/app.env` (0600), not in the repo** | Terraform-generated passwords never enter version control; `.gitignore` excludes `*.tfvars`, state and `*.pem`. |
| 15 | **Installer gzipped into EC2 user-data** | The raw base64 bootstrap measured 15.7 KiB against EC2's 16 KiB cap; `base64gzip` plus a Terraform precondition keeps the plan honest. |

---

## 8. Cost control, then teardown

1. Billing → **Budgets** → monthly cost budget, amount **$1**, alert at 50/80/100 %.
2. Billing → **Cost Explorer**, group by service, filter `us-east-1`, and screenshot
   the first 24 hours showing EC2 + RDS only.
3. Confirm no NAT gateway, no load balancer, no snapshots in EC2/EC2→Volumes.

**S12** — Billing → Cost Explorer (or Budgets) showing the $1 budget and current spend.

Teardown when you have your screenshots (this is the only reliable way to stop billing):

```bash
cd infra && terraform destroy     # removes EC2, RDS, EIP, VPC, SGs
```
Manual: terminate the instance, delete the RDS instance (**skip final snapshot**
if you do not need the data), release the Elastic IP, delete the VPC.

---

## 9. Verification and evidence

Run on the instance:

```bash
# 1. The database is not local - nothing listens on 3306 here
ss -ltnp | grep 3306 || echo "OK: no MySQL on the app server"

# 2. The database really is a different host
mysql -h "$(grep '^DB_HOST' /etc/prestashop/app.env | cut -d'"' -f2)" \
      -u ps_app -p prestashop -e 'SELECT @@hostname, @@version, @@port;'
# @@hostname must be an ip-10-20-x-x... RDS host, NOT the EC2 hostname

# 3. Table count proves the schema lives remotely
mysql -h "$(grep '^DB_HOST' /etc/prestashop/app.env | cut -d'"' -f2)" \
      -u ps_app -p prestashop -e 'SELECT COUNT(*) AS tables FROM information_schema.tables WHERE table_schema="prestashop";'
# ~250+ tables after a fixtures install

# 4. Services
systemctl is-active nginx php8.1-fpm
```

Then confirm the installer is gone from the web root: open
`http://127.0.0.1/install/` in a browser — a **403 Forbidden** is the correct answer.

Run from your laptop:

```bash
./scripts/verify-deployment.sh http://ec2-x-x-x-x.compute-1.amazonaws.com/
```

**S13** — `ss -ltnp | grep 3306` returning nothing **and** the `SELECT @@hostname` output showing the RDS host (this is the strongest single piece of evidence for the separate-database requirement).
**S14** — `verify-deployment.sh` output, all PASS.

---

## 10. Screenshot checklist

See [screenshot-checklist.md](screenshot-checklist.md) for the annotated list of
S1–S16, what each frame must contain, and which requirement it proves.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Installer: `Your server is running PHP 8.3... requires PHP 7.2.5 and 8.1` | Ubuntu 24.04 image | Use Ubuntu 22.04 (PHP 8.1), or install `php8.1` from the ondrej PPA — not supported by this script |
| `ERROR: cannot reach <rds>:3306` | DB SG missing the app SG rule, RDS in a public subnet pair, or wrong endpoint | Compare S2/S4, then try the mysql client from the EC2 box against the endpoint |
| Storefront shows 502 | PHP-FPM down or socket path mismatch | `systemctl status php8.1-fpm`, `tail /var/log/nginx/prestashop.error.log`, check the socket name in the vhost |
| Storefront shows 500 after install | Directory permissions, or `/install` missing but schema incomplete | Re-run the installer (idempotent); `chown -R www-data:www-data /var/www/html` |
| Admin page redirects to `localhost` | Installed with the wrong `--domain` | Back office → **Shop Parameters → Traffic & SEO** → set the shop domain, then clear `/var/www/html/var/cache/*` |
| Product links 404 | Friendly URLs on but rewrite rules not loaded | Keep `--rewrite=0`, or confirm the `try_files $uri $uri/ /index.php?$args;` block and reload Nginx |
| `apt-get` lock / transient failures at boot | cloud-init racing unattended-upgrades | The script retries `apt-get update` 30× and is safe to re-run |
| Disk full during import | 20 GB root volume is tight with images | Resize the volume in EC2 → Volumes, then `growpart` + `resize2fs` |
| Can't SSH | `admin_cidr` not your current IP, or key permissions | Update the `<project>-app-sg` rule; `chmod 600 *.pem` |

---

## 12. Security notes (for the "design decisions" section of the report)

* Port 22 restricted to the operator's /32; 80/443 open because the store is public by requirement.
* Database: private subnets, no default route, inbound only from the app SG, encryption at rest, dedicated least-privilege application user.
* IMDSv2 enforced on the instance; no IAM role with broad permissions attached (the box needs none).
* Secrets: generated by Terraform, written to `/etc/prestashop/app.env` (0600) and `/root/prestashop-summary.txt` (0600); excluded from git.
* Weaknesses of this *assignment* deployment, stated honestly: plain HTTP (no TLS without a domain), PrestaShop's demo fixtures and default theme left in place, admin password delivered via EC2 user-data (visible to anyone with `ec2:DescribeInstances`), single-AZ database. Production would add ACM/Let's Encrypt TLS on a real domain, SSM Parameter Store or Secrets Manager for credentials, a WAF, and Multi-AZ RDS.

---

## 13. Appendix — alternative free hosting (if AWS signup is not possible)

The brief allows "AWS or similar". Oracle Cloud **Always Free** is the closest
free substitute and also satisfies the separate-database rule:

* 2 × Ampere A1 VMs (4 OCPU / 24 GB total) — one for Nginx + PHP 8.1, one for MySQL 8.0, both permanently free.
* Or one VM plus **MySQL HeatWave Always Free** (managed, 50 GB) if your tenancy offers it.
* Public IP + default `*.oraclecloud.com` hostname is included; open ports 80/443 in the VCN security list, keep 3306 restricted to the web VM's private IP.
* Reuse `scripts/install-prestashop.sh` unchanged — set `DB_HOST` to the database VM's **private** IP and create the schema user there first.

Azure/GCP equivalents: B1s (Azure, 12-month) + Azure Database for MySQL flexible server Burstable B1ms; GCP `e2-micro` free VM + no free managed MySQL (Cloud SQL has no always-free tier, so use a second free VM).

---

## 14. File map

```
infra/versions.tf             Terraform + provider pins, default tags
infra/variables.tf            inputs, free-tier defaults, validations
infra/main.tf                 VPC, subnets, SGs, RDS, EC2, EIP, bootstrap user-data
infra/outputs.tf              store_url, ssh_command, db_endpoint, next steps
infra/terraform.tfvars.example  copy to terraform.tfvars
scripts/install-prestashop.sh   idempotent installer (used by user-data or by hand)
scripts/deploy-aws-cli.sh       one-shot AWS CLI/CloudShell provisioner (installer embedded)
scripts/destroy-aws-cli.sh      removes everything the CLI provisioner created
scripts/verify-deployment.sh    external PASS/FAIL checks from your laptop
docs/implementation-runbook.md  this document
docs/cloudshell-deploy.md       deploy from the browser console with no local tooling
docs/screenshot-checklist.md    S1-S16 capture guide
```
