#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/down.sh <your-name>
# Example: ./scripts/down.sh stef

NAME="${1:-}"

if [ -z "$NAME" ]; then
  echo "Usage: ./scripts/down.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd -- "$SCRIPT_DIR/../terraform" && pwd)"

cd "$INFRA_DIR"

echo ">> Connecting kubectl to the cluster..."
aws eks update-kubeconfig \
  --name "eks-${NAME}" \
  --region "${REGION}" \
  >/dev/null 2>&1 || true

echo ">> Removing LoadBalancer services..."

for namespace in $(kubectl get namespaces \
  -o jsonpath='{.items[*].metadata.name}' \
  2>/dev/null || true); do

  for service in $(kubectl get services \
    --namespace "$namespace" \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{" "}{end}' \
    2>/dev/null || true); do

    echo "   deleting service '$service' in namespace '$namespace'"

    kubectl delete service "$service" \
      --namespace "$namespace" || true
  done
done

echo ">> Waiting for AWS load balancers to be removed..."
sleep 20

echo ">> Destroying EKS infrastructure..."
terraform destroy \
  -auto-approve \
  -var="student_name=${NAME}" \
  -var="region=${REGION}"

echo ">> Infrastructure deleted."