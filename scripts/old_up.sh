#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/up.sh <your-name>
# Example: ./scripts/up.sh stef

NAME="${1:-}"

if [ -z "$NAME" ]; then
  echo "Usage: ./scripts/up.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd -- "$SCRIPT_DIR/../terraform" && pwd)"

cd "$INFRA_DIR"

echo ">> Initialising Terraform..."
terraform init -input=false

echo ">> Creating EKS infrastructure..."
terraform apply \
  -auto-approve \
  -var="student_name=${NAME}" \
  -var="region=${REGION}"

echo ">> Connecting kubectl to the cluster..."
aws eks update-kubeconfig \
  --name "eks-${NAME}" \
  --region "${REGION}"

echo ">> Cluster nodes:"
kubectl get nodes