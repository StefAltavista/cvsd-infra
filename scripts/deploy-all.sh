#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-voting-app}"

"$SCRIPT_DIR/deploy-config.sh"
"$SCRIPT_DIR/deploy-postgres.sh"
"$SCRIPT_DIR/deploy-redis.sh"
"$SCRIPT_DIR/deploy-worker.sh"
"$SCRIPT_DIR/deploy-vote.sh"
"$SCRIPT_DIR/deploy-result.sh"

echo
echo ">> Complete application deployment succeeded."
kubectl get statefulsets,deployments,services,pods,pvc   -n "$NAMESPACE"   -o wide
