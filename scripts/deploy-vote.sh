#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"
NAMESPACE="${NAMESPACE:-voting-app}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

echo ">> Deploying vote service..."
kubectl apply -f "$K8S_DIR/vote/service.yaml"
kubectl apply -f "$K8S_DIR/vote/deployment.yaml"

kubectl rollout status deployment/vote   -n "$NAMESPACE"   --timeout="$TIMEOUT"

echo ">> Vote service is ready."
kubectl get pods   -n "$NAMESPACE"   -l app.kubernetes.io/name=vote   -o wide

echo
echo "Test locally with:"
echo "kubectl port-forward -n $NAMESPACE service/vote-service 8080:80"
