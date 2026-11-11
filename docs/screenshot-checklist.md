# Screenshot checklist (S1–S16)

These frames **must be captured by the account owner** from the AWS Console and a
browser; the environment that wrote this runbook has no AWS access, so no console
screenshots are included. Each row states what must be legible in the frame and
which requirement it proves. Number the files `s01-...png` … `s16-...png` so they
match the report.

Tips: capture the **whole browser window including the URL bar** for anything
web-facing; keep the region selector (`us-east-1`) visible in console shots;
blur account IDs, access keys and passwords, but never blur instance type,
endpoint, subnet CIDR or security-group rules — those are the evidence.

| # | Where | Frame must show | Proves |
|---|---|---|---|
| S1 | VPC → Your VPCs → resource map | `prestashop-vpc`, CIDR `10.20.0.0/16`, 2 public + 2 private subnets, NAT gateway *None* | Network segmentation decision (no NAT cost) |
| S2 | EC2 → Security Groups → `prestashop-db-sg` → Inbound | One rule: MySQL 3306, source = `sg-…` app SG name; no CIDR rules | Database only reachable from the app tier |
| S3 | RDS → Databases → `prestashop-mysql` | Engine MySQL 8.0, class `db.t4g.micro`, Status **Available**, **Publicly accessible: No** | Separate managed database + free-tier class |
| S4 | Same instance → *Connectivity & security* | Endpoint hostname + port 3306, VPC, DB subnet group (private subnets), SG | Database is a distinct host on a private network |
| S5 | EC2 → Instances | `prestashop-app`: Running, `t4g.small`, Public IPv4 + Public DNS, AZ, SG | New server instance, free-eligible size |
| S6 | EC2 → Instance → Storage | Single 20 GiB gp3 root volume, encrypted | No database on the app server; storage within free tier |
| S7 | EC2 → Elastic IPs | EIP associated with `prestashop-app` / i-… | Stable public URL |
| S8 | SSH terminal | `sudo tail -n 40 /var/log/prestashop-install.log` with `-- Installation successful! --` | PrestaShop actually installed |
| S9 | SSH terminal | `sudo cat /root/prestashop-summary.txt` (blur passwords) | Admin URL, DB endpoint, versions |
| S10 | Browser | Back-office dashboard, `http://ec2-…/adminXXXX/` in the URL bar, shop name in header | Working admin |
| S11 | Browser | Storefront home page, full URL in the URL bar | **Submitted public URL** |
| S12 | Billing → Budgets or Cost Explorer | $1 budget, current spend, EC2 + RDS only | Free-tier discipline |
| S13 | SSH terminal | `ss -ltnp \| grep 3306` → nothing, then `SELECT @@hostname` returning the RDS host | **Strongest proof DB is not on the app server** |
| S14 | Laptop terminal | `./scripts/verify-deployment.sh <url>` all PASS | External verification |
| S15 | RDS → instance → Maintenance & backups | Single-AZ, backup retention 1 day | Free-tier configuration decision |
| S16 | EC2 → Security Groups → `prestashop-app-sg` | 22 from `<your-ip>/32`, 80/443 from 0.0.0.0/0 | SSH least exposure |

Optional but good for marks: the Terraform `plan`/`apply` summary (resource
count), and a MySQL client view of `information_schema.tables` showing the
PrestaShop schema living on the RDS host.
