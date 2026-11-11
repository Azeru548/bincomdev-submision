#!/usr/bin/env bash
#
# deploy-aws-cli.sh - provision the whole PrestaShop split-tier stack with the
# AWS CLI only (no Terraform, no local installs). Designed to be pasted into
# AWS CloudShell, where the CLI is already authenticated with your credentials.
#
# Creates: VPC + 2 public/2 private subnets in 2 AZs, IGW + route tables,
#          app/db security groups, RDS MySQL 8.0 (private), EC2 Ubuntu 22.04
#          arm64 running Nginx + PHP 8.1-FPM + PrestaShop 8.2.x, Elastic IP.
#
# Usage in CloudShell:
#   export ADMIN_CIDR="$(curl -s https://checkip.amazonaws.com)/32"
#   bash deploy-aws-cli.sh
#
# Re-running is safe: existing resources are found by tag/name and reused.
# Tear everything down with: bash destroy-aws-cli.sh
#
# NOTE: the PrestaShop installer is embedded below as a gzipped base64 payload,
# generated from scripts/install-prestashop.sh. Regenerate after editing it with:
#   python3 - <<'PY'
#   import base64,gzip,pathlib,re
#   src=pathlib.Path('scripts/install-prestashop.sh').read_bytes()
#   b=base64.b64encode(gzip.compress(src,9)).decode()
#   p=pathlib.Path('scripts/deploy-aws-cli.sh'); t=p.read_text()
#   t=re.sub(r'INSTALLER_B64_GZIP="[^"]*"', 'INSTALLER_B64_GZIP="%s"'%b, t)
#   p.write_text(t)
#   PY
#
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Settings (override with environment variables)
# ---------------------------------------------------------------------------
REGION="${REGION:-us-east-1}"
PROJECT="${PROJECT:-prestashop}"
ADMIN_CIDR="${ADMIN_CIDR:-}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.small}"
DB_CLASS="${DB_CLASS:-db.t4g.micro}"
PS_VERSION="${PS_VERSION:-8.2.9}"
SHOP_NAME="${SHOP_NAME:-PrestaShop on AWS}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-PrestaShop2026!Demo}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-Store}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-Admin}"

DB_IDENTIFIER="${PROJECT}-mysql"
DB_ADMIN_USER="psadmin"
DB_APP_USER="ps_app"
DB_NAME="prestashop"
VPC_CIDR="10.20.0.0/16"

# Embedded installer (gzipped, base64). Kept in one line so the generated
# user-data stays shell-safe.
INSTALLER_B64_GZIP="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"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# aws with region and text output; "None" becomes empty.
q() {
  local out
  out="$(aws --region "$REGION" --output text "$@" 2>/dev/null || true)"
  [[ "$out" == "None" ]] && out=""
  printf '%s' "$out"
}

gen_pw() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v aws >/dev/null 2>&1 || die "AWS CLI not found. Run this in AWS CloudShell."
[[ -n "$ADMIN_CIDR" ]] || die "Set ADMIN_CIDR first:
  export ADMIN_CIDR=\"\$(curl -s https://checkip.amazonaws.com)/32\""
[[ "$ADMIN_CIDR" == */* ]] || ADMIN_CIDR="${ADMIN_CIDR}/32"
[[ -n "${INSTALLER_B64_GZIP}" && "$INSTALLER_B64_GZIP" != "__INSTALLER_PAYLOAD__" ]] \
  || die "installer payload missing - regenerate it with the python snippet in this file's header"

ACCOUNT="$(q sts get-caller-identity --query Account)" && [[ -n "$ACCOUNT" ]] \
  || die "AWS CLI is not authenticated in this shell"

log "Account ${ACCOUNT}, region ${REGION}, project ${PROJECT}"
log "Instance ${INSTANCE_TYPE}, database ${DB_CLASS}, SSH from ${ADMIN_CIDR}"

# ---------------------------------------------------------------------------
# 1. VPC
# ---------------------------------------------------------------------------
VPC="$(q ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT}-vpc" \
        --query 'Vpcs[0].VpcId')"
if [[ -z "$VPC" ]]; then
  log "Creating VPC ${VPC_CIDR}"
  VPC="$(q ec2 create-vpc --cidr-block "$VPC_CIDR" --query 'Vpc.VpcId')"
  q ec2 create-tags --resources "$VPC" --tags "Key=Name,Value=${PROJECT}-vpc" "Key=Project,Value=${PROJECT}" >/dev/null
  q ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames '{"Value":true}' >/dev/null
  q ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-support '{"Value":true}' >/dev/null
else
  log "Reusing VPC ${VPC}"
fi

# ---------------------------------------------------------------------------
# 2. Subnets (2 public, 2 private, spread over 2 AZs)
# ---------------------------------------------------------------------------
read -r AZ1 AZ2 <<<"$(q ec2 describe-availability-zones --query 'AvailabilityZones[0:2].ZoneName')"
[[ -n "${AZ1:-}" && -n "${AZ2:-}" ]] || die "could not resolve two availability zones"

ensure_subnet() { # name cidr az [public]
  local name="$1" cidr="$2" az="$3" public="${4:-no}" id
  id="$(q ec2 describe-subnets --filters "Name=tag:Name,Values=$name" "Name=vpc-id,Values=$VPC" \
        --query 'Subnets[0].SubnetId')"
  if [[ -z "$id" ]]; then
    id="$(q ec2 create-subnet --vpc-id "$VPC" --cidr-block "$cidr" \
           --availability-zone "$az" --query 'Subnet.SubnetId')"
    q ec2 create-tags --resources "$id" --tags "Key=Name,Value=$name" "Key=Project,Value=$PROJECT" >/dev/null
    [[ "$public" == "yes" ]] && q ec2 modify-subnet-attribute --subnet-id "$id" --map-public-ip-on-launch >/dev/null
    log "Created subnet $name ($cidr, $az)"
  fi
  printf '%s' "$id"
}

PUB_A="$(ensure_subnet "${PROJECT}-public-a" 10.20.10.0/24 "$AZ1" yes)"
PUB_B="$(ensure_subnet "${PROJECT}-public-b" 10.20.11.0/24 "$AZ2" yes)"
PRIV_A="$(ensure_subnet "${PROJECT}-private-a" 10.20.20.0/24 "$AZ1" no)"
PRIV_B="$(ensure_subnet "${PROJECT}-private-b" 10.20.21.0/24 "$AZ2" no)"

# ---------------------------------------------------------------------------
# 3. Internet gateway, route tables
# ---------------------------------------------------------------------------
IGW="$(q ec2 describe-internet-gateways --filters "Name=tag:Name,Values=${PROJECT}-igw" \
        --query 'InternetGateways[0].InternetGatewayId')"
if [[ -z "$IGW" ]]; then
  IGW="$(q ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId')"
  q ec2 create-tags --resources "$IGW" --tags "Key=Name,Value=${PROJECT}-igw" >/dev/null
  log "Created internet gateway $IGW"
fi
q ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC" >/dev/null || true

PUB_RT="$(q ec2 describe-route-tables --filters "Name=tag:Name,Values=${PROJECT}-public-rt" "Name=vpc-id,Values=$VPC" --query 'RouteTables[0].RouteTableId')"
if [[ -z "$PUB_RT" ]]; then
  PUB_RT="$(q ec2 create-route-table --vpc-id "$VPC" --query 'RouteTable.RouteTableId')"
  q ec2 create-tags --resources "$PUB_RT" --tags "Key=Name,Value=${PROJECT}-public-rt" >/dev/null
  log "Created public route table $PUB_RT"
fi
q ec2 create-route --route-table-id "$PUB_RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null || true

for sub in "$PUB_A" "$PUB_B"; do
  q ec2 associate-route-table --route-table-id "$PUB_RT" --subnet-id "$sub" >/dev/null || true
done

# Private route tables: no default route at all. RDS needs no egress and the
# database stays unreachable from the internet.
for pair in "A:$PRIV_A" "B:$PRIV_B"; do
  tag="${pair%%:*}"; sub="${pair##*:}"
  PRT="$(q ec2 describe-route-tables --filters "Name=tag:Name,Values=${PROJECT}-private-${tag}-rt" "Name=vpc-id,Values=$VPC" --query 'RouteTables[0].RouteTableId')"
  if [[ -z "$PRT" ]]; then
    PRT="$(q ec2 create-route-table --vpc-id "$VPC" --query 'RouteTable.RouteTableId')"
    q ec2 create-tags --resources "$PRT" --tags "Key=Name,Value=${PROJECT}-private-${tag}-rt" >/dev/null
  fi
  q ec2 associate-route-table --route-table-id "$PRT" --subnet-id "$sub" >/dev/null || true
done

# ---------------------------------------------------------------------------
# 4. Security groups
# ---------------------------------------------------------------------------
APP_SG="$(q ec2 describe-security-groups --filters "Name=group-name,Values=${PROJECT}-app-sg" "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[0].GroupId')"
if [[ -z "$APP_SG" ]]; then
  APP_SG="$(q ec2 create-security-group --group-name "${PROJECT}-app-sg" \
             --description "PrestaShop web server" --vpc-id "$VPC" --query 'GroupId')"
  q ec2 create-tags --resources "$APP_SG" --tags "Key=Name,Value=${PROJECT}-app-sg" >/dev/null
  log "Created app security group $APP_SG"
fi

# Public web ports, SSH only from the operator address.
for rule in "80:0.0.0.0/0" "443:0.0.0.0/0" "22:${ADMIN_CIDR}"; do
  port="${rule%%:*}"; cidr="${rule##*:}"
  aws --region "$REGION" ec2 authorize-security-group-ingress \
    --group-id "$APP_SG" --protocol tcp --port "$port" --cidr "$cidr" >/dev/null 2>&1 || true
done

DB_SG="$(q ec2 describe-security-groups --filters "Name=group-name,Values=${PROJECT}-db-sg" "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[0].GroupId')"
if [[ -z "$DB_SG" ]]; then
  DB_SG="$(q ec2 create-security-group --group-name "${PROJECT}-db-sg" \
            --description "PrestaShop MySQL - app tier only" --vpc-id "$VPC" --query 'GroupId')"
  q ec2 create-tags --resources "$DB_SG" --tags "Key=Name,Value=${PROJECT}-db-sg" >/dev/null
  log "Created database security group $DB_SG"
fi

# 3306 from the application security group only - never a CIDR.
aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$DB_SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=3306,ToPort=3306,UserIdGroupPairs=[{GroupId=${APP_SG},Description=app-tier-only}]" \
  >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 5. Database (RDS MySQL 8.0, private subnets)
# ---------------------------------------------------------------------------
q rds create-db-subnet-group --db-subnet-group-name "${PROJECT}-db-subnets" \
  --db-subnet-group-description "PrestaShop private database subnets" \
  --subnet-ids "$PRIV_A" "$PRIV_B" >/dev/null 2>&1 || true

DB_EXISTS="$(q rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
              --query 'DBInstances[0].DBInstanceStatus')"

DB_ADMIN_PASSWORD_FILE="$HOME/${PROJECT}-db-admin-password.txt"
if [[ -z "$DB_EXISTS" ]]; then
  DB_ADMIN_PASSWORD="$(gen_pw)"
  umask 077
  printf '%s\n' "$DB_ADMIN_PASSWORD" > "$DB_ADMIN_PASSWORD_FILE"

  log "Creating RDS ${DB_CLASS} (MySQL 8.0) - this takes 8-12 minutes"
  q rds create-db-instance \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --db-instance-class "$DB_CLASS" \
    --engine mysql --engine-version 8.0 \
    --allocated-storage 20 --storage-type gp2 --storage-encrypted \
    --master-username "$DB_ADMIN_USER" --master-user-password "$DB_ADMIN_PASSWORD" \
    --db-name "$DB_NAME" --backup-retention-period 1 \
    --no-multi-az --no-publicly-accessible \
    --vpc-security-group-ids "$DB_SG" \
    --db-subnet-group-name "${PROJECT}-db-subnets" \
    --no-performance-insights --no-deletion-protection \
    --tags "Key=Name,Value=${PROJECT}-mysql" >/dev/null
else
  log "RDS instance already exists (${DB_EXISTS}) - reusing it"
  DB_ADMIN_PASSWORD="$(cat "$DB_ADMIN_PASSWORD_FILE" 2>/dev/null || true)"
  [[ -n "$DB_ADMIN_PASSWORD" ]] || die "existing RDS found but ${DB_ADMIN_PASSWORD_FILE} is missing;
reset the master password in the console, or set DB_ADMIN_PASSWORD yourself."
fi

log "Waiting for RDS to become available"
for i in $(seq 1 60); do
  status="$(q rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0].DBInstanceStatus')"
  [[ "$status" == "available" ]] && break
  printf '   [%02d/60] status=%s\n' "$i" "${status:-creating}"
  sleep 20
  [[ $i -eq 60 ]] && die "RDS did not become available in 20 minutes"
done

DB_HOST="$(q rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0].Endpoint.Address')"
DB_PORT="$(q rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0].Endpoint.Port')"
[[ -n "$DB_HOST" ]] || die "could not read the RDS endpoint"
log "Database endpoint: ${DB_HOST}:${DB_PORT}"

# ---------------------------------------------------------------------------
# 6. Application server
# ---------------------------------------------------------------------------
AMI="$(q ssm get-parameter --name "/aws/service/canonical/ubuntu/server/22.04/stable/current/arm64/hvm/ebs-gp2/ami-id" --query 'Parameter.Value')"
[[ -n "$AMI" ]] || die "could not resolve the Ubuntu 22.04 arm64 AMI from SSM"

KEY_NAME="${PROJECT}-key"
KEY_FILE="$HOME/${PROJECT}-key.pem"
if [[ -n "$(q ec2 describe-key-pairs --key-names "$KEY_NAME" --query 'KeyPairs[0].KeyName')" ]]; then
  if [[ ! -f "$KEY_FILE" ]]; then
    KEY_NAME="${PROJECT}-key-$(date +%s)"
    warn "key pair ${PROJECT}-key already exists but ${KEY_FILE} is gone; creating ${KEY_NAME}"
  fi
fi
if [[ ! -f "$KEY_FILE" ]]; then
  umask 077
  q ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  log "Created SSH key pair ${KEY_NAME} -> ${KEY_FILE}"
fi

DB_APP_PASSWORD="$(gen_pw)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log "Building user-data (credentials + embedded installer)"
cat > "$WORKDIR/user-data.sh" <<USERDATA
#!/bin/bash
set -euo pipefail
install -d -m 0750 /etc/prestashop
umask 077
cat > /etc/prestashop/app.env <<'APPENV'
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT}"
DB_NAME="${DB_NAME}"
DB_ADMIN_USER="${DB_ADMIN_USER}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD}"
DB_APP_USER="${DB_APP_USER}"
DB_APP_PASSWORD="${DB_APP_PASSWORD}"
SHOP_NAME="${SHOP_NAME}"
SHOP_EMAIL="${ADMIN_EMAIL}"
ADMIN_EMAIL="${ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME}"
ADMIN_LASTNAME="${ADMIN_LASTNAME}"
TIMEZONE="UTC"
COUNTRY="us"
LANGUAGE="en"
PS_VERSION="${PS_VERSION}"
APPENV
chmod 0600 /etc/prestashop/app.env
echo '${INSTALLER_B64_GZIP}' | base64 -d | gunzip > /usr/local/sbin/install-prestashop.sh
chmod 0755 /usr/local/sbin/install-prestashop.sh
/usr/local/sbin/install-prestashop.sh
USERDATA

INSTANCE="$(q ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PROJECT}-app" "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[0].Instances[0].InstanceId')"

if [[ -z "$INSTANCE" ]]; then
  log "Launching ${INSTANCE_TYPE} application server"
  INSTANCE="$(q ec2 run-instances \
    --image-id "$AMI" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$APP_SG" \
    --subnet-id "$PUB_A" \
    --associate-public-ip-address \
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}" \
    --user-data "file://${WORKDIR}/user-data.sh" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-app},{Key=Project,Value=${PROJECT}}]" \
    --query 'Instances[0].InstanceId')"
  log "Instance ${INSTANCE} launched - waiting for running state"
else
  log "Reusing instance ${INSTANCE} (bootstrap already ran on first boot)"
fi

q ec2 wait instance-running --instance-ids "$INSTANCE"

EIP_ALLOC="$(q ec2 describe-addresses --filters "Name=tag:Name,Values=${PROJECT}-eip" --query 'Addresses[0].AllocationId')"
if [[ -z "$EIP_ALLOC" ]]; then
  EIP_ALLOC="$(q ec2 allocate-address --domain vpc --query 'AllocationId')"
  q ec2 create-tags --resources "$EIP_ALLOC" --tags "Key=Name,Value=${PROJECT}-eip" >/dev/null
  log "Allocated Elastic IP ${EIP_ALLOC}"
fi
q ec2 associate-address --instance-id "$INSTANCE" --allocation-id "$EIP_ALLOC" >/dev/null || true

PUBLIC_DNS="$(q ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].PublicDnsName')"
PUBLIC_IP="$(q ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].PublicIpAddress')"

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
cat <<SUMMARY

================================================================
 Deployment requested. Provisioning is still running on the box.
================================================================
 Storefront URL   : http://${PUBLIC_DNS:-$PUBLIC_IP}/
 Public IP        : ${PUBLIC_IP}
 SSH              : ssh -i ${KEY_FILE} ubuntu@${PUBLIC_IP}
 Database (RDS)   : ${DB_HOST}:${DB_PORT}  (separate host, private subnet)
 App instance     : ${INSTANCE} (${INSTANCE_TYPE}, Ubuntu 22.04 arm64)
 DB password file : ${DB_ADMIN_PASSWORD_FILE}
 Region           : ${REGION}

 Next steps
 1. Wait 6-10 minutes, then watch the bootstrap:
      ssh -i ${KEY_FILE} ubuntu@${PUBLIC_IP} 'sudo tail -f /var/log/prestashop-install.log'
 2. Read the admin URL and credentials:
      ssh -i ${KEY_FILE} ubuntu@${PUBLIC_IP} 'sudo cat /root/prestashop-summary.txt'
 3. Open the storefront, then verify from your laptop:
      ./scripts/verify-deployment.sh http://${PUBLIC_DNS:-$PUBLIC_IP}/

 In CloudShell, download the private key to your laptop with
   Actions -> Download file  ->  ${KEY_FILE}
 (CloudShell's home directory is not your local disk.)

 Tear down everything with: bash destroy-aws-cli.sh
SUMMARY
