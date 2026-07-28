#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/tls-up.sh <your-name>
# Example: ./scripts/tls-up.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/tls-up.sh <your-name>"
  exit 1
fi

REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${DOMAIN:-ironlabs.online}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

echo ">> Connecting to EKS..."
aws eks update-kubeconfig \
  --name "eks-${NAME}" \
  --region "$REGION"

echo ">> Installing cert-manager..."
helm upgrade --install cert-manager \
  oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.0 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait \
  --timeout 5m

echo ">> Applying Let's Encrypt issuers..."
kubectl apply \
  -f "$REPO_DIR/kubernetes/cert-manager/cluster-issuers.yaml"

kubectl wait \
  --for=condition=Ready \
  clusterissuer/letsencrypt-prod \
  --timeout=2m

echo ">> Applying HTTPS application routing..."
kubectl apply \
  -f "$REPO_DIR/kubernetes/ingress/voting-app-ingress.yaml"

echo ">> Waiting for TLS certificate..."
kubectl wait \
  --namespace voting-app \
  --for=condition=Ready \
  certificate/voting-app-tls \
  --timeout=10m

echo ">> HTTPS ready:"
echo "   https://vote.${NAME}.${DOMAIN}"
echo "   https://result.${NAME}.${DOMAIN}"