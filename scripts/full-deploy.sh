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

echo ">> 1/4 Creating EKS infrastructure..."
"$SCRIPT_DIR/infra-up.sh" "$NAME"

echo
echo ">> 2/4 Deploying application workloads..."
"$SCRIPT_DIR/deploy-all-services.sh"

echo
echo ">> 3/4 Installing ingress-nginx and routing..."
"$SCRIPT_DIR/ingress-up.sh" "$NAME"

echo
echo ">> 4/4 Creating Route 53 records..."
"$SCRIPT_DIR/dns-up.sh" "$NAME"

echo
echo ">> Full deployment complete."
echo ">> Vote:  http://vote.${NAME}.${DOMAIN}"
echo ">> Result: http://result.${NAME}.${DOMAIN}"
