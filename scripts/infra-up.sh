#!/usr/bin/env bash


set -euo pipefail

# Usage: ./scripts/up.sh <your-name>
# Example: ./scripts/up.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/up.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd -- "$SCRIPT_DIR/../terraform" && pwd)"

cd "$TERRAFORM_DIR"

echo ">> Formatting Terraform..."
terraform fmt -check

echo ">> Initialising Terraform..."
terraform init -input=false -upgrade

echo ">> Validating Terraform..."
terraform validate

echo ">> Creating EKS infrastructure..."
terraform apply   -input=false   -auto-approve   -var="student_name=${NAME}"   -var="region=${REGION}"

CLUSTER_NAME="$(terraform output -raw cluster_name)"

echo ">> Connecting kubectl to ${CLUSTER_NAME}..."
aws eks update-kubeconfig   --name "$CLUSTER_NAME"   --region "$REGION"

echo ">> Waiting for worker nodes..."
kubectl wait   --for=condition=Ready   nodes   --all   --timeout=10m

echo ">> Cluster nodes:"
kubectl get nodes -o wide

echo ">> EKS add-ons:"
aws eks list-addons   --cluster-name "$CLUSTER_NAME"   --region "$REGION"   --output table

echo ">> Infrastructure is ready."
echo ">> Deploy the application with: ./scripts/deploy-all.sh"
