#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"
NAMESPACE="${NAMESPACE:-voting-app}"
SECRET_FILE="$K8S_DIR/config/app-secrets.yaml"

if [[ ! -f "$SECRET_FILE" ]]; then
  echo "Error: $SECRET_FILE does not exist."
  echo "Copy app-secrets.example.yaml and add the real PostgreSQL password."
  exit 1
fi

echo ">> Applying namespace, storage, configuration, and secrets..."
kubectl apply -f "$K8S_DIR/namespace.yaml"
kubectl apply -f "$K8S_DIR/storage/gp3-storage-class.yaml"
kubectl apply -f "$K8S_DIR/config/app-config.yaml"
kubectl apply -f "$SECRET_FILE"

echo ">> Base configuration is ready."
kubectl get namespace "$NAMESPACE"
kubectl get storageclass gp3
kubectl get configmap voting-app-config -n "$NAMESPACE"
