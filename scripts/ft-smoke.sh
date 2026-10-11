#!/usr/bin/env bash
# fast-track kit: "is everything really working?" in one command. Run ON THE WORKSTATION.
#   scripts/ft-smoke.sh            platform + all three envs (status, endpoints, a real checkout per env)
#   scripts/ft-smoke.sh dev        one env only
#   scripts/ft-smoke.sh --wait     keep re-checking every 15 s until everything is green (use right after make up)
# Exit code 0 = all green. Prints the measured time, so you can quote it ("full rebuild in N minutes").
set -uo pipefail
ENVS="dev qa prod"; WAIT=no
for a in "$@"; do case "$a" in --wait) WAIT=yes;; dev|qa|prod) ENVS=$a;; esac; done
START=$(date +%s); PASS=0; FAIL=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
api()  { curl -s -m 10 -H "Host: $1.roboshop.test" "${@:3}" "http://localhost$2"; }
code() { curl -s -m 10 -o /dev/null -w '%{http_code}' -H "Host: $1.roboshop.test" "http://localhost$2"; }

run_checks() {
  PASS=0; FAIL=0
  echo "== platform"
  nr=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l)
  [ "$nr" -eq 0 ] && ok "kind nodes Ready ($(kubectl get nodes --no-headers | wc -l))" || bad "$nr node(s) not Ready"
  apps=$(kubectl -n argocd get applications --no-headers 2>/dev/null)
  total=$(echo "$apps" | grep -c . || true)
  notok=$(echo "$apps" | awk 'NF && ($2!="Synced" || ($3!="Healthy" && $3!="Suspended"))')
  if [ -n "$apps" ] && [ -z "$notok" ]; then ok "Argo CD: $total/$total apps Synced + Healthy"
  else bad "Argo CD: $(echo "$notok" | grep -c .)/$total not ready:"; echo "$notok" | awk 'NF{printf "      %-34s %-10s %s\n",$1,$2,$3}' | head -15; fi
  es=$(kubectl get externalsecrets -A --no-headers 2>/dev/null | awk '$NF!="True"' | grep -c . || true)
  [ "$es" -eq 0 ] && ok "ExternalSecrets all Ready (SSM -> Kubernetes Secrets)" || bad "$es ExternalSecret(s) not Ready: kubectl get externalsecrets -A"

  for e in $ENVS; do
    echo "== $e  (http://$e.roboshop.test:8080 through make tunnel)"
    np=$(kubectl -n roboshop-$e get pods --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed"' )
    [ -z "$np" ] && ok "pods Running ($(kubectl -n roboshop-$e get pods --no-headers 2>/dev/null | wc -l))" \
                 || { bad "pods not Running:"; echo "$np" | awk '{printf "      %-40s %s\n",$1,$3}' | head -8; }
    for p in / /api/catalogue/health /api/user/health /api/cart/health /api/shipping/health /api/payment/health \
             /api/ratings/_health /api/catalogue/categories /api/shipping/count; do
      c=$(code $e $p); [ "$c" = 200 ] && ok "GET $p" || bad "GET $p -> $c"
    done
    # A real order: anonymous user -> cart -> shipping (mysql) -> payment -> rabbitmq -> dispatch
    id=$(api $e /api/user/uniqueid | jq -r '.uuid // empty' 2>/dev/null)
    if [ -z "$id" ]; then bad "checkout: no uniqueid from user service"; continue; fi
    api $e "/api/cart/add/$id/Watson/1" >/dev/null
    cc=$(api $e /api/shipping/codes | jq -r '.[0].code // empty' 2>/dev/null)
    cid=$(api $e "/api/shipping/match/$cc/a" | jq -r '.[0].uuid // empty' 2>/dev/null)
    ship=$(api $e "/api/shipping/calc/$cid" 2>/dev/null | jq -c '. + {location: "ft-smoke"}' 2>/dev/null)
    [ -n "$ship" ] || ship='{}'
    cart=$(api $e "/api/cart/shipping/$id" -X POST -H 'Content-Type: application/json' -d "$ship")
    [ -n "$cart" ] || cart='{}'
    order=$(api $e "/api/payment/pay/$id" -X POST -H 'Content-Type: application/json' -d "$cart" | jq -r '.orderid // empty' 2>/dev/null)
    [ -n "$order" ] && ok "checkout end-to-end: order $order (cart -> shipping -> payment -> rabbitmq)" \
                    || bad "checkout failed (user=$id city=$cid) - see 08-troubleshooting-fast.md#checkout"
  done
  echo "== $PASS passed, $FAIL failed   ($(( ($(date +%s)-START)/60 ))m$(( ($(date +%s)-START)%60 ))s since start)"
  [ "$FAIL" -eq 0 ]
}

if [ "$WAIT" = yes ]; then
  until run_checks; do echo "   ...not green yet, re-checking in 15 s (Ctrl-C to stop)"; sleep 15; clear 2>/dev/null || true; done
  echo "ALL GREEN after $(( ($(date +%s)-START)/60 ))m$(( ($(date +%s)-START)%60 ))s  <- write this number down (rebuild RTO)"
else
  run_checks
fi
