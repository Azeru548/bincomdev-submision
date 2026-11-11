#!/usr/bin/env bash
#
# destroy-aws-cli.sh - remove everything deploy-aws-cli.sh created.
#
#   bash destroy-aws-cli.sh
#
# Deletes: EC2 instance, Elastic IP, key pair, RDS instance (no final snapshot),
#          security groups, DB subnet group, subnets, route tables, IGW, VPC.
# Ordering matters: the VPC cannot be deleted until its children are gone.
#
set -Eeuo pipefail

REGION="${REGION:-us-east-1}"
PROJECT="${PROJECT:-prestashop}"
DB_IDENTIFIER="${PROJECT}-mysql"

log() { printf '\n==> %s\n' "$*"; }
q() {
  local out
  out="$(aws --region "$REGION" --output text "$@" 2>/dev/null || true)"
  [[ "$out" == "None" ]] && out=""
  printf '%s' "$out"
}

VPC="$(q ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT}-vpc" --query 'Vpcs[0].VpcId')"
if [[ -z "$VPC" ]]; then
  log "No VPC tagged ${PROJECT}-vpc found - nothing to remove"
  exit 0
fi

log "Removing project ${PROJECT} in ${VPC}"

# 1. Application server
for id in $(q ec2 describe-instances \
      --filters "Name=tag:Project,Values=${PROJECT}" \
      --query 'Reservations[].Instances[].InstanceId'); do
  log "Terminating instance $id"
  q ec2 terminate-instances --instance-ids "$id" >/dev/null
done
for id in $(q ec2 describe-instances \
      --filters "Name=tag:Project,Values=${PROJECT}" "Name=instance-state-name,Values=shutting-down,stopping,stopped" \
      --query 'Reservations[].Instances[].InstanceId'); do
  q ec2 wait instance-terminated --instance-ids "$id" || true
done

# 2. Elastic IPs (an unattached EIP is billed)
for alloc in $(q ec2 describe-addresses --filters "Name=tag:Project,Values=${PROJECT}" --query 'Addresses[].AllocationId'); do
  log "Releasing Elastic IP $alloc"
  q ec2 release-address --allocation-id "$alloc" >/dev/null || true
done

# 3. Database
if [[ -n "$(q rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0].DBInstanceIdentifier')" ]]; then
  log "Deleting RDS $DB_IDENTIFIER (no final snapshot)"
  q rds delete-db-instance --db-instance-identifier "$DB_IDENTIFIER" \
    --skip-final-snapshot --delete-automated-backups >/dev/null || true
  for i in $(seq 1 60); do
    st="$(q rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0].DBInstanceStatus')"
    [[ -z "$st" ]] && break
    printf '   waiting for RDS deletion [%02d/60] %s\n' "$i" "$st"
    sleep 20
  done
fi

# 4. Key pairs
for k in $(q ec2 describe-key-pairs --filters "Name=key-name,Values=${PROJECT}-key*" --query 'KeyPairs[].KeyName'); do
  log "Deleting key pair $k"
  q ec2 delete-key-pair --key-name "$k" >/dev/null || true
done

# 5. Security groups, subnet group, subnets, route tables, IGW, VPC
for sg in $(q ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" "Name=group-name,Values=${PROJECT}-*" --query 'SecurityGroups[].GroupId'); do
  log "Deleting security group $sg"
  q ec2 delete-security-group --group-id "$sg" >/dev/null || true
done

q rds delete-db-subnet-group --db-subnet-group-name "${PROJECT}-db-subnets" >/dev/null 2>&1 || true

for rt in $(q ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" "Name=tag:Project,Values=${PROJECT}" --query 'RouteTables[].RouteTableId'); do
  for assoc in $(q ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[].Associations[?Main!=`true`].RouteTableAssociationId[]'); do
    q ec2 disassociate-route-table --association-id "$assoc" >/dev/null || true
  done
  log "Deleting route table $rt"
  q ec2 delete-route-table --route-table-id "$rt" >/dev/null || true
done

for sub in $(q ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" "Name=tag:Project,Values=${PROJECT}" --query 'Subnets[].SubnetId'); do
  log "Deleting subnet $sub"
  q ec2 delete-subnet --subnet-id "$sub" >/dev/null || true
done

for igw in $(q ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId'); do
  log "Detaching and deleting internet gateway $igw"
  q ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC" >/dev/null || true
  q ec2 delete-internet-gateway --internet-gateway-id "$igw" >/dev/null || true
done

log "Deleting VPC $VPC"
q ec2 delete-vpc --vpc-id "$VPC" >/dev/null || printf 'VPC still has dependencies; re-run in a minute.\n'

log "Done. Verify in the console that EC2, RDS and Elastic IP lists are empty."
