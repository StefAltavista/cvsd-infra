#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$REPO_DIR/kubernetes"

NAMESPACE="${NAMESPACE:-voting-app}"
TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

declare -A IMAGES=(
  ["vote"]="stefltv/voting-python-service:latest"
  ["result"]="stefltv/results-node-service:latest"
  ["worker"]="stefltv/worker-net-service:latest"
)

DEPLOYMENTS=(
  "vote"
  "result"
  "worker"
)

echo ">> Deploying application services"
echo ">> Namespace: $NAMESPACE"

echo
echo ">> Applying vote resources..."
kubectl apply -f "$K8S_DIR/vote/service.yaml"
kubectl apply -f "$K8S_DIR/vote/deployment.yaml"

echo
echo ">> Applying result resources..."
kubectl apply -f "$K8S_DIR/result/service.yaml"
kubectl apply -f "$K8S_DIR/result/deployment.yaml"

echo
echo ">> Applying worker resources..."
kubectl apply -f "$K8S_DIR/worker/deployment.yaml"

echo
echo ">> Configuring application container images..."

for deployment in "${DEPLOYMENTS[@]}"; do
  image="${IMAGES[$deployment]}"

  container_name="$(
    kubectl get deployment "$deployment" \
      --namespace "$NAMESPACE" \
      --output jsonpath='{.spec.template.spec.containers[0].name}'
  )"

  if [[ -z "$container_name" ]]; then
    echo "ERROR: Could not find the container name for deployment/$deployment."
    exit 1
  fi

  echo
  echo ">> Configuring deployment/$deployment"
  echo "   Container: $container_name"
  echo "   Image:     $image"
  echo "   Pull:      Always"

  kubectl patch deployment "$deployment" \
    --namespace "$NAMESPACE" \
    --type strategic \
    --patch \
    "{
      \"spec\": {
        \"template\": {
          \"spec\": {
            \"containers\": [
              {
                \"name\": \"$container_name\",
                \"image\": \"$image\",
                \"imagePullPolicy\": \"Always\"
              }
            ]
          }
        }
      }
    }"
done

echo
echo ">> Restarting application deployments..."

for deployment in "${DEPLOYMENTS[@]}"; do
  echo ">> Restarting deployment/$deployment"

  kubectl rollout restart \
    "deployment/$deployment" \
    --namespace "$NAMESPACE"
done

echo
echo ">> Waiting for rollouts..."

for deployment in "${DEPLOYMENTS[@]}"; do
  echo
  echo ">> Waiting for deployment/$deployment"

  kubectl rollout status \
    "deployment/$deployment" \
    --namespace "$NAMESPACE" \
    --timeout="$TIMEOUT"
done

echo
echo ">> Current application pods:"

kubectl get pods \
  --namespace "$NAMESPACE" \
  --selector 'app.kubernetes.io/name in (vote,result,worker)' \
  --output wide

echo
echo ">> Application deployment completed successfully."