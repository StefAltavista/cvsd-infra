#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"
NAMESPACE="${NAMESPACE:-voting-app}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

echo ">> Deploying worker..."
kubectl apply -f "$K8S_DIR/worker/deployment.yaml"

kubectl rollout status deployment/worker   -n "$NAMESPACE"   --timeout="$TIMEOUT"

echo ">> Worker is ready."
kubectl get pods   -n "$NAMESPACE"   -l app.kubernetes.io/name=worker   -o wide
