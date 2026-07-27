#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/dns-up.sh <your-name>
# Example: ./scripts/dns-up.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/dns-up.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${DOMAIN:-ironlabs.online}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DNS_DIR="$(cd -- "$SCRIPT_DIR/../terraform-dns" && pwd)"

INGRESS_HOST="$(
  kubectl get service ingress-nginx-controller \
    --namespace ingress-nginx \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'
)"

INGRESS_ZONE_ID="$(
  aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?DNSName=='${INGRESS_HOST}'].CanonicalHostedZoneId | [0]" \
    --output text
)"

cd "$DNS_DIR"

echo ">> Initialising Route 53 Terraform..."
terraform init -input=false

echo ">> Creating Route 53 records..."
terraform apply \
  -input=false \
  -auto-approve \
  -var="region=${REGION}" \
  -var="student_name=${NAME}" \
  -var="hosted_zone_name=${DOMAIN}" \
  -var="ingress_hostname=${INGRESS_HOST}" \
  -var="ingress_zone_id=${INGRESS_ZONE_ID}"

echo ">> DNS ready:"
echo "   http://vote.${NAME}.${DOMAIN}"
echo "   http://result.${NAME}.${DOMAIN}"