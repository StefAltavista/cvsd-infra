#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"
NAMESPACE="${NAMESPACE:-voting-app}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

echo ">> Deploying result service..."
kubectl apply -f "$K8S_DIR/result/service.yaml"
kubectl apply -f "$K8S_DIR/result/deployment.yaml"

kubectl rollout status deployment/result   -n "$NAMESPACE"   --timeout="$TIMEOUT"

echo ">> Result service is ready."
kubectl get pods   -n "$NAMESPACE"   -l app.kubernetes.io/name=result   -o wide

echo
echo "Test locally with:"
echo "kubectl port-forward -n $NAMESPACE service/result-service 8081:80"
