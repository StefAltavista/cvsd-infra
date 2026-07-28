#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/full-deploy.sh <your-name>
# Example: ./scripts/full-deploy.sh stef

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  echo "Usage: ./scripts/full-deploy.sh <your-name>"
  exit 1
fi

DOMAIN="${DOMAIN:-ironlabs.online}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo ">> 1/5 Creating EKS infrastructure..."
"$SCRIPT_DIR/infra-up.sh" "$NAME"

echo
echo ">> 2/5 Deploying application workloads..."
"$SCRIPT_DIR/deploy-all-services.sh"

echo
echo ">> 3/5 Installing ingress-nginx..."
"$SCRIPT_DIR/ingress-up.sh" "$NAME"

echo
echo ">> 4/5 Creating Route 53 records..."
"$SCRIPT_DIR/dns-up.sh" "$NAME"

echo
echo ">> 5/5 Configuring TLS..."
"$SCRIPT_DIR/tls-up.sh" "$NAME"

echo
echo ">> Full deployment complete."
echo ">> Vote:  https://vote.${NAME}.${DOMAIN}"
echo ">> Result: https://result.${NAME}.${DOMAIN}"