#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"
NAMESPACE="${NAMESPACE:-voting-app}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

echo ">> Deploying PostgreSQL..."
kubectl apply -f "$K8S_DIR/postgres/service.yaml"
kubectl apply -f "$K8S_DIR/postgres/statefulset.yaml"

kubectl rollout status statefulset/postgres   -n "$NAMESPACE"   --timeout="$TIMEOUT"

kubectl exec -n "$NAMESPACE" postgres-0 -- /bin/sh -c   'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

echo ">> PostgreSQL is ready."
kubectl get pod/postgres-0 -n "$NAMESPACE" -o wide
kubectl get pvc/postgres-data-postgres-0 -n "$NAMESPACE"
