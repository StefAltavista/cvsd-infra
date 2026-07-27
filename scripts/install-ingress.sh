#!/usr/bin/env bash


# Requires Helm:
# curl -fsSL -o get_helm.sh \
#  https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4

# chmod 700 get_helm.sh
# ./get_helm.sh


set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

VALUES_FILE="$REPO_DIR/helm/ingress-nginx-values.yaml"
NAMESPACE="ingress-nginx"
RELEASE_NAME="ingress-nginx"
CHART_VERSION="4.15.1"

if ! command -v helm >/dev/null 2>&1; then
  echo "Error: Helm is not installed."
  exit 1
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Error: Helm values file not found:"
  echo "  $VALUES_FILE"
  exit 1
fi

echo ">> Adding the ingress-nginx Helm repository..."
helm repo add \
  ingress-nginx \
  https://kubernetes.github.io/ingress-nginx \
  --force-update

echo ">> Updating the Helm repository..."
helm repo update ingress-nginx

echo ">> Installing ingress-nginx..."

helm upgrade \
  --install "$RELEASE_NAME" \
  ingress-nginx/ingress-nginx \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --version "$CHART_VERSION" \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 10m

echo ">> ingress-nginx controller pods:"
kubectl get pods \
  --namespace "$NAMESPACE" \
  -o wide

echo
echo ">> ingress-nginx controller service:"
kubectl get service \
  ingress-nginx-controller \
  --namespace "$NAMESPACE"

echo
echo ">> IngressClass:"
kubectl get ingressclass nginx

echo
echo ">> ingress-nginx installation complete."
echo ">> The AWS load balancer hostname may take a few minutes to appear."