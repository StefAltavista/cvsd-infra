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
CLUSTER_NAME="eks-${NAME}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd -- "$SCRIPT_DIR/../terraform" && pwd)"

cd "$TERRAFORM_DIR"

echo ">> Initialising Terraform..."
terraform init -input=false

echo ">> Connecting kubectl to ${CLUSTER_NAME}..."
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  >/dev/null 2>&1 || true

echo ">> Removing application Ingress resources..."
kubectl delete ingress \
  --all \
  --namespace voting-app \
  --ignore-not-found \
  || true

echo ">> Removing NGINX Ingress Controller..."
helm uninstall ingress-nginx \
  --namespace ingress-nginx \
  >/dev/null 2>&1 || true

kubectl delete namespace ingress-nginx \
  --ignore-not-found \
  --wait=true \
  --timeout=5m \
  || true

echo ">> Removing the voting application and persistent volumes..."
kubectl delete namespace voting-app \
  --ignore-not-found \
  --wait=true \
  --timeout=10m \
  || true

echo ">> Waiting for AWS load balancers and EBS volumes to be removed..."
sleep 30

echo ">> Destroying EKS infrastructure..."
terraform destroy \
  -input=false \
  -auto-approve \
  -var="student_name=${NAME}" \
  -var="region=${REGION}"

echo ">> Infrastructure deleted."