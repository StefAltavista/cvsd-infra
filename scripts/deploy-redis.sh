#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"
NAMESPACE="${NAMESPACE:-voting-app}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

echo ">> Deploying Redis..."
kubectl apply -f "$K8S_DIR/redis/service.yaml"
kubectl apply -f "$K8S_DIR/redis/statefulset.yaml"

kubectl rollout status statefulset/redis   -n "$NAMESPACE"   --timeout="$TIMEOUT"

kubectl exec -n "$NAMESPACE" redis-0 -- redis-cli ping

echo ">> Redis is ready."
kubectl get pod/redis-0 -n "$NAMESPACE" -o wide
kubectl get pvc/redis-data-redis-0 -n "$NAMESPACE"
