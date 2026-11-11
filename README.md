# PrestaShop on AWS (Free Tier) — deployment package

PrestaShop 8.2.9 on an EC2 application server with MySQL 8.0 on a **separate
Amazon RDS host**, inside AWS Free Tier limits.

> **Status.** Terraform and the installer are complete and statically validated
> (`terraform validate`, `terraform fmt`, ShellCheck). **Nothing has been deployed**
> — this workspace has no AWS account or credentials — so there is no live URL and
> no AWS Console screenshots here. Those are produced when *you* run the stack in
> your own account; [docs/screenshot-checklist.md](docs/screenshot-checklist.md)
> lists exactly what to capture.

## Start here

Read **[docs/implementation-runbook.md](docs/implementation-runbook.md)** — it is
the submission document: architecture, free-tier reasoning, both the automated
path and the manual AWS Console click-through, decision log, verification commands,
troubleshooting and teardown.

**Already have an AWS account and want it deployed in one command?** Use
**[docs/cloudshell-deploy.md](docs/cloudshell-deploy.md)** — paste a single script
into AWS CloudShell (already authenticated, nothing to install locally, no keys
handled anywhere else):

```bash
export ADMIN_CIDR="$(curl -s https://checkip.amazonaws.com)/32"
./scripts/deploy-aws-cli.sh      # ~20 min, prints the public URL
```

## Fast track

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # set admin_cidr = <your-ip>/32
terraform init && terraform plan -out tfplan && terraform apply tfplan

terraform output store_url        # <- the URL you submit
ssh -i prestashop-key.pem ubuntu@$(terraform output -raw public_ip) \
    'sudo cat /root/prestashop-summary.txt'   # admin URL + credentials
```

From your laptop, verify the finished site:

```bash
./scripts/verify-deployment.sh "$(cd infra && terraform output -raw store_url)"
```

## What gets built

| Layer | Resource | Free-tier reasoning |
|---|---|---|
| Network | VPC `10.20.0.0/16`, 2 public + 2 private subnets, IGW, **no NAT gateway** | RDS needs no egress; NAT would cost ~$32/month |
| App | EC2 `t4g.small`, Ubuntu 22.04 arm64, 20 GB gp3, Elastic IP | T4g trial free through 2026-12-31 on any account |
| App software | Nginx + PHP 8.1-FPM + PrestaShop 8.2.9 | 8.2.9 refuses PHP > 8.1, so 22.04 not 24.04 |
| Data | RDS MySQL 8.0 `db.t4g.micro`, 20 GB gp2, single-AZ, private subnets | Free-eligible class; not on the app server |

## Files

```
infra/                        Terraform: versions, variables, main, outputs, tfvars example
scripts/install-prestashop.sh Idempotent installer (also runs as EC2 user-data)
scripts/deploy-aws-cli.sh     One-shot AWS CLI/CloudShell provisioner (installer embedded)
scripts/destroy-aws-cli.sh    Removes everything deploy-aws-cli.sh created
scripts/verify-deployment.sh  External PASS/FAIL checks
docs/implementation-runbook.md  Main submission document
docs/cloudshell-deploy.md       Deploy from the browser console, no local tooling
docs/screenshot-checklist.md    S1-S16 capture guide
```

## Verified in this workspace

* `terraform fmt -check` and `terraform validate` pass.
* `bash -n` and `shellcheck -S warning` are clean on both scripts.
* The PrestaShop 8.2.9 release layout was inspected: the official ZIP is a wrapper
  holding `prestashop.zip` plus a web launcher, and `install/index_cli.php` caps PHP
  at 8.1 — both findings are handled by the installer.
* The installer is gzipped into EC2 user-data (base64 would exceed the 16 KiB
  limit), with a Terraform precondition that fails the plan if it ever grows past it.
* `scripts/verify-deployment.sh` was exercised against a mock server: it reports
  PASS/FAIL per check, exits 1 when any check fails and 2 with no arguments.
* Not verified: the AWS apply itself, the boot-time apt/download run, and the live
  storefront — those require your account.
