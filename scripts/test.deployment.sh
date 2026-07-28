#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/test-deployment.sh <your-name>
# Example: ./scripts/test-deployment.sh stef
#
# Optional:
# SLOW_THRESHOLD=2 ./scripts/test-deployment.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/test-deployment.sh <your-name>"
  exit 1
fi

NAMESPACE="${NAMESPACE:-voting-app}"
DOMAIN="${DOMAIN:-ironlabs.online}"
SLOW_THRESHOLD="${SLOW_THRESHOLD:-1}"
TEST_IMAGE="${TEST_IMAGE:-curlimages/curl:8.10.1}"

VOTE_HOST="vote.${NAME}.${DOMAIN}"
RESULT_HOST="result.${NAME}.${DOMAIN}"
INGRESS_SERVICE="ingress-nginx-controller.ingress-nginx.svc.cluster.local"

FAILURES=0
SLOW_REQUESTS=0
TEST_PODS=()

cleanup() {
  if (( ${#TEST_PODS[@]} > 0 )); then
    kubectl delete pod \
      --namespace "$NAMESPACE" \
      "${TEST_PODS[@]}" \
      --ignore-not-found \
      --wait=false \
      >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

for command in kubectl curl awk; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: ${command} is required."
    exit 1
  fi
done

mapfile -t NODES < <(
  kubectl get nodes \
    --no-headers \
    --output custom-columns=':metadata.name'
)

if (( ${#NODES[@]} == 0 )); then
  echo "Error: no Kubernetes worker nodes found."
  exit 1
fi

echo ">> Checking workload readiness..."
kubectl wait \
  --namespace "$NAMESPACE" \
  --for=condition=Ready \
  pod \
  --all \
  --timeout=5m

echo
echo ">> Current application Pods:"
kubectl get pods \
  --namespace "$NAMESPACE" \
  --output wide

echo
echo ">> Endpoint placement:"

for SERVICE in vote-service result-service; do
  echo
  echo "   ${SERVICE}"

  kubectl get endpointslice \
    --namespace "$NAMESPACE" \
    --selector="kubernetes.io/service-name=${SERVICE}" \
    --output=jsonpath='{range .items[*].endpoints[*]}{"   "}{.addresses[0]}{" ready="}{.conditions.ready}{" node="}{.nodeName}{"\n"}{end}'
done

echo
echo ">> Creating one network tester on each worker node..."

for index in "${!NODES[@]}"; do
  NODE="${NODES[$index]}"
  POD="network-check-${index}-$$"
  TEST_PODS+=("$POD")

  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD}
  namespace: ${NAMESPACE}
spec:
  nodeName: ${NODE}
  restartPolicy: Never
  automountServiceAccountToken: false
  containers:
    - name: curl
      image: ${TEST_IMAGE}
      command:
        - sh
        - -c
        - sleep 600
EOF

  kubectl wait \
    --namespace "$NAMESPACE" \
    --for=condition=Ready \
    "pod/${POD}" \
    --timeout=2m \
    >/dev/null

  echo "   ${POD} → ${NODE}"
done

mapfile -t VOTE_ENDPOINTS < <(
  kubectl get endpointslice \
    --namespace "$NAMESPACE" \
    --selector="kubernetes.io/service-name=vote-service" \
    --output=jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
)

mapfile -t RESULT_ENDPOINTS < <(
  kubectl get endpointslice \
    --namespace "$NAMESPACE" \
    --selector="kubernetes.io/service-name=result-service" \
    --output=jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
)

internal_request() {
  local pod="$1"
  local label="$2"
  local url="$3"
  local host_header="${4:-}"
  local output
  local -a curl_args

  curl_args=(
    curl
    --fail
    --silent
    --show-error
    --connect-timeout 2
    --max-time 4
    --output /dev/null
    --write-out "connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s"
  )

  if [[ -n "$host_header" ]]; then
    curl_args+=(-H "Host: ${host_header}")
  fi

  curl_args+=("$url")

  if output="$(
    kubectl exec \
      --namespace "$NAMESPACE" \
      "$pod" \
      -- "${curl_args[@]}" \
      2>&1
  )"; then
    echo "   PASS ${label}: ${output}"
  else
    echo "   FAIL ${label}: ${output}"
    FAILURES=$((FAILURES + 1))
  fi
}

for index in "${!TEST_PODS[@]}"; do
  POD="${TEST_PODS[$index]}"
  NODE="${NODES[$index]}"

  echo
  echo "===== Tests from ${NODE} ====="

  echo
  echo ">> Direct vote Pod connections"

  for IP in "${VOTE_ENDPOINTS[@]}"; do
    internal_request \
      "$POD" \
      "vote ${IP}" \
      "http://${IP}:80/"
  done

  echo
  echo ">> Direct result Pod connections"

  for IP in "${RESULT_ENDPOINTS[@]}"; do
    internal_request \
      "$POD" \
      "result ${IP}" \
      "http://${IP}:80/"
  done

  echo
  echo ">> Kubernetes Service routing"

  for attempt in {1..6}; do
    internal_request \
      "$POD" \
      "vote-service attempt ${attempt}" \
      "http://vote-service/"

    internal_request \
      "$POD" \
      "result-service attempt ${attempt}" \
      "http://result-service/"
  done

  echo
  echo ">> Internal ingress routing"

  for attempt in {1..6}; do
    internal_request \
      "$POD" \
      "vote ingress attempt ${attempt}" \
      "http://${INGRESS_SERVICE}/" \
      "$VOTE_HOST"

    internal_request \
      "$POD" \
      "result ingress attempt ${attempt}" \
      "http://${INGRESS_SERVICE}/" \
      "$RESULT_HOST"
  done
done

echo
echo "===== Public domain latency ====="

for HOST in "$VOTE_HOST" "$RESULT_HOST"; do
  echo
  echo ">> ${HOST}"

  for attempt in {1..10}; do
    if METRICS="$(
      curl \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 2 \
        --max-time 4 \
        --output /dev/null \
        --write-out "%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total}" \
        "http://${HOST}/" \
        2>&1
    )"; then
      read -r DNS_TIME CONNECT_TIME TTFB TOTAL_TIME <<< "$METRICS"

      printf \
        "   %02d dns=%ss connect=%ss ttfb=%ss total=%ss" \
        "$attempt" \
        "$DNS_TIME" \
        "$CONNECT_TIME" \
        "$TTFB" \
        "$TOTAL_TIME"

      if awk \
        -v value="$TOTAL_TIME" \
        -v limit="$SLOW_THRESHOLD" \
        'BEGIN { exit !(value > limit) }'
      then
        echo " SLOW"
        SLOW_REQUESTS=$((SLOW_REQUESTS + 1))
      else
        echo " PASS"
      fi
    else
      echo "   ${attempt} FAIL: ${METRICS}"
      FAILURES=$((FAILURES + 1))
    fi
  done
done

echo
echo "===== Test summary ====="
echo "Connectivity failures: ${FAILURES}"
echo "Requests over ${SLOW_THRESHOLD}s: ${SLOW_REQUESTS}"

if (( FAILURES > 0 || SLOW_REQUESTS > 0 )); then
  echo "Deployment networking test failed."
  exit 1
fi

echo "All connectivity and latency tests passed."