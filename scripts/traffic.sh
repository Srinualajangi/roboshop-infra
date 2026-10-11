#!/usr/bin/env bash
# Usage: scripts/traffic.sh <dev|qa|prod> [seconds]   — sends browser-like requests through Traefik on :80
set -euo pipefail
ENV=${1:-dev}; DUR=${2:-300}; HOST="${ENV}.roboshop.test"
PATHS=(/ /api/catalogue/products /api/catalogue/categories /api/user/uniqueid)
END=$((SECONDS+DUR)); n=0
while [ $SECONDS -lt $END ]; do
  for p in "${PATHS[@]}"; do
    curl -s -o /dev/null -w '%{http_code}\n' -H "Host: ${HOST}" "http://localhost${p}" || echo 000
    n=$((n+1))
  done
done | sort | uniq -c
echo "sent ~$n requests to $HOST"
