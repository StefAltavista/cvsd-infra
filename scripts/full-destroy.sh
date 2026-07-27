#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/down.sh <your-name>
# Example: ./scripts/down.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/down.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${DOMAIN:-ironlabs.online}"
CLUSTER_NAME="eks-${NAME}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd -- "$SCRIPT_DIR/../terraform" && pwd)"
DNS_DIR="$(cd -- "$SCRIPT_DIR/../terraform-dns" && pwd)"

echo ">> Connecting kubectl to ${CLUSTER_NAME}..."
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  >/dev/null 2>&1 || true

echo ">> Reading ingress load balancer details..."

INGRESS_HOST="$(
  kubectl get service ingress-nginx-controller \
    --namespace ingress-nginx \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null || true
)"

# Fallback when the cluster is already partially unavailable.
if [[ -z "$INGRESS_HOST" ]]; then
  INGRESS_HOST="$(
    terraform -chdir="$DNS_DIR" output -raw ingress_hostname \
      2>/dev/null || true
  )"
fi

LOAD_BALANCER_ARN=""
INGRESS_ZONE_ID=""

if [[ -n "$INGRESS_HOST" ]]; then
  LOAD_BALANCER_ARN="$(
    aws elbv2 describe-load-balancers \
      --region "$REGION" \
      --query "LoadBalancers[?DNSName=='${INGRESS_HOST}'].LoadBalancerArn | [0]" \
      --output text \
      2>/dev/null || true
  )"

  INGRESS_ZONE_ID="$(
    aws elbv2 describe-load-balancers \
      --region "$REGION" \
      --query "LoadBalancers[?DNSName=='${INGRESS_HOST}'].CanonicalHostedZoneId | [0]" \
      --output text \
      2>/dev/null || true
  )"
fi

echo ">> Removing Route 53 records..."
terraform -chdir="$DNS_DIR" init -input=false

DNS_STATE="$(
  terraform -chdir="$DNS_DIR" state list \
    2>/dev/null || true
)"

if [[ -n "$DNS_STATE" ]]; then
  terraform -chdir="$DNS_DIR" destroy \
    -input=false \
    -auto-approve \
    -var="region=${REGION}" \
    -var="student_name=${NAME}" \
    -var="hosted_zone_name=${DOMAIN}" \
    -var="ingress_hostname=${INGRESS_HOST}" \
    -var="ingress_zone_id=${INGRESS_ZONE_ID}"
else
  echo "   no Route 53 resources found"
fi

echo ">> Recording persistent volumes..."

APP_VOLUMES="$(
  kubectl get pvc \
    --namespace voting-app \
    --output jsonpath='{range .items[*]}{.spec.volumeName}{" "}{end}' \
    2>/dev/null || true
)"

echo ">> Removing application Ingress..."
kubectl delete ingress \
  --all \
  --namespace voting-app \
  --ignore-not-found \
  || true

echo ">> Removing ingress-nginx..."
helm uninstall ingress-nginx \
  --namespace ingress-nginx \
  --wait \
  --timeout 10m \
  >/dev/null 2>&1 || true

kubectl delete namespace ingress-nginx \
  --ignore-not-found \
  --wait=true \
  --timeout=10m \
  || true

if [[ -n "$LOAD_BALANCER_ARN" && "$LOAD_BALANCER_ARN" != "None" ]]; then
  echo ">> Deleting the AWS Network Load Balancer..."

  aws elbv2 delete-load-balancer \
    --region "$REGION" \
    --load-balancer-arn "$LOAD_BALANCER_ARN"

  echo ">> Waiting for the Network Load Balancer to disappear..."

  aws elbv2 wait load-balancers-deleted \
    --region "$REGION" \
    --load-balancer-arns "$LOAD_BALANCER_ARN"
fi

echo ">> Removing the voting application and persistent data..."
kubectl delete namespace voting-app \
  --ignore-not-found \
  --wait=true \
  --timeout=10m \
  || true

for volume in $APP_VOLUMES; do
  echo ">> Waiting for persistent volume ${volume} to be deleted..."

  kubectl wait \
    --for=delete \
    "persistentvolume/${volume}" \
    --timeout=10m \
    2>/dev/null || true
done

echo ">> Initialising infrastructure Terraform..."
terraform -chdir="$TERRAFORM_DIR" init -input=false

echo ">> Destroying EKS infrastructure..."
terraform -chdir="$TERRAFORM_DIR" destroy \
  -input=false \
  -auto-approve \
  -var="student_name=${NAME}" \
  -var="region=${REGION}"

echo ">> Everything has been deleted."