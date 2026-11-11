# Deploying from AWS CloudShell (no local installs, no Terraform)

You have an AWS account. This is the shortest path from "blank account" to a
running PrestaShop store with the database on a separate host.

## Why CloudShell

CloudShell is a browser terminal **inside your AWS Console**, already
authenticated as your IAM user. That means:

* no access keys leave your account, and none are pasted into a chat;
* nothing to install locally (AWS CLI, git and python are preinstalled);
* `deploy-aws-cli.sh` is a single self-contained file.

What this route does **not** do is click through the console UI for you. Driving
the console on your behalf would require your credentials in a browser session
this workspace cannot reach, so the automation runs as CLI calls against your
own authenticated session instead. The console screenshots you need for the
report are still captured by you afterwards — the resources will already exist.

## Steps

1. Open **AWS Console → CloudShell** (region selector: `us-east-1`).
2. Upload the script: CloudShell → **Actions → Upload file** →
   `scripts/deploy-aws-cli.sh`. Then:

   ```bash
   chmod +x deploy-aws-cli.sh
   export ADMIN_CIDR="$(curl -s https://checkip.amazonaws.com)/32"
   ./deploy-aws-cli.sh
   ```

   Or paste it inline if you prefer: `cat > deploy-aws-cli.sh` then paste, then
   `Ctrl-D`.

3. The script prints progress. RDS takes 8–12 minutes; the EC2 bootstrap then
   needs another 6–10 minutes. Total ≈ 20 minutes, unattended.

   > Keep the session active. CloudShell times out after ~20–30 minutes of
   > inactivity; if it does, the deployment keeps running on AWS — reconnect and
   > continue from step 4.

4. Download your SSH key: **Actions → Download file** → `~/prestashop-key.pem`.
   CloudShell's home is not your laptop's disk; this is how the key gets out.
   `chmod 600 prestashop-key.pem` after downloading.

5. Watch the bootstrap and read the credentials:

   ```bash
   ssh -i ~/prestashop-key.pem ubuntu@<public-ip> \
       'sudo tail -f /var/log/prestashop-install.log'
   ssh -i ~/prestashop-key.pem ubuntu@<public-ip> \
       'sudo cat /root/prestashop-summary.txt'
   ```

6. Open the storefront URL. Then verify from anywhere:

   ```bash
   ./scripts/verify-deployment.sh http://<public-dns>/
   ```

7. Capturing the AWS Console evidence is now just navigation: EC2 → Instances,
   RDS → Databases, VPC → resource map, EC2 → Security Groups. Use
   [screenshot-checklist.md](screenshot-checklist.md) — every resource the
   checklist asks for already exists.

## What it creates

Identical to the Terraform stack: VPC `10.20.0.0/16` with 2 public + 2 private
subnets in 2 AZs, IGW, two security groups (`3306` from the app SG only), RDS
MySQL 8.0 `db.t4g.micro` in the private subnets with no route to the internet,
EC2 `t4g.small` (Ubuntu 22.04 arm64) running Nginx + PHP 8.1-FPM + PrestaShop
8.2.9, and an Elastic IP whose default AWS hostname is your public URL.

Re-running the script reuses existing resources; it does not duplicate them.

## Settings you can override

```bash
REGION=us-east-1
INSTANCE_TYPE=t3.micro      # legacy free-tier accounts
DB_CLASS=db.t3.micro
SHOP_NAME="My Store"
ADMIN_EMAIL=you@example.com
ADMIN_PASSWORD='SomethingStrong!2026'
PS_VERSION=8.2.9
```

## Cleanup

```bash
bash destroy-aws-cli.sh
```

This terminates the instance, deletes RDS (no final snapshot), releases the
Elastic IP, and removes the SGs, subnets, route tables, IGW and VPC. An
unattached Elastic IP and a forgotten RDS instance are the two things that keep
billing you — this script removes both.

## Note on the embedded installer

The PrestaShop installer is embedded in `deploy-aws-cli.sh` as a gzipped base64
blob (EC2 caps user-data at 16 KiB). If you edit
`scripts/install-prestashop.sh`, regenerate the payload with the Python snippet
in the deploy script's header comment, otherwise the old installer ships.
