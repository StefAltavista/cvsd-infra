#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/ingress-up.sh <your-name>
# Example: ./scripts/ingress-up.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/ingress-up.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

echo ">> Connecting to EKS..."
aws eks update-kubeconfig \
  --name "eks-${NAME}" \
  --region "$REGION"

echo ">> Installing ingress-nginx..."
helm repo add \
  ingress-nginx \
  https://kubernetes.github.io/ingress-nginx \
  --force-update

helm upgrade --install ingress-nginx \
  ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values "$REPO_DIR/helm/ingress-nginx-values.yaml" \
  --wait \
  --timeout 10m

echo ">> Applying application routing..."
kubectl apply \
  -f "$REPO_DIR/kubernetes/ingress/voting-app-ingress.yaml"

echo ">> Waiting for AWS load balancer..."

until INGRESS_HOST="$(
  kubectl get service ingress-nginx-controller \
    --namespace ingress-nginx \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null
)" && [[ -n "$INGRESS_HOST" ]]; do
  sleep 5
done

echo ">> Ingress ready:"
echo "   ${INGRESS_HOST}"