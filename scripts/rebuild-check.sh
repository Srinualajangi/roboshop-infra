#!/usr/bin/env bash
# Run ON THE WORKSTATION after make up. Prints how long until everything is Synced+Healthy and the shops answer.
set -uo pipefail
start=$(date +%s)
while true; do
  bad=$(kubectl -n argocd get applications --no-headers 2>/dev/null | awk '$2!="Synced" || $3!="Healthy"' | wc -l)
  total=$(kubectl -n argocd get applications --no-headers 2>/dev/null | wc -l)
  codes=""
  for h in dev qa prod; do codes="$codes $h:$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $h.roboshop.test" http://localhost/api/catalogue/health)"; done
  printf '\r%4ss  apps not ready: %2s/%-2s  %s   ' $(( $(date +%s)-start )) "$bad" "$total" "$codes"
  if [ "$total" -gt 0 ] && [ "$bad" -eq 0 ] && ! grep -qv ':200' <<<"$(tr ' ' '\n' <<<"$codes" | sed '/^$/d')"; then
    echo; echo "ALL GREEN after $(( $(date +%s)-start ))s (since this script started)"; exit 0
  fi
  sleep 10
done
