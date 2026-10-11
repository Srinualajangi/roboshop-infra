#!/usr/bin/env bash
# healthcheck.sh - check every RoboShop component on the legacy host.
# Usage: healthcheck.sh [-q] [-t TIMEOUT]   -q: only print failures   -t: curl timeout seconds (default 3)
# Exit codes: 0 all healthy, 1 one or more checks failed, 2 usage error.
set -euo pipefail

TIMEOUT=3
QUIET=false
while getopts ":qt:h" opt; do
  case "$opt" in
    q) QUIET=true ;;
    t) TIMEOUT="$OPTARG" ;;
    h) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "usage: $0 [-q] [-t TIMEOUT]" >&2; exit 2 ;;
  esac
done

# colours only when writing to a terminal (not in the journal or a pipe)
if [ -t 1 ]; then GREEN=$'\e[32m'; RED=$'\e[31m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'; else GREEN=""; RED=""; YELLOW=""; RESET=""; fi

FAILED=0
declare -a FAILURES=()

ok()   { $QUIET || printf '%s[ OK ]%s %-22s %s\n' "$GREEN" "$RESET" "$1" "$2"; }
fail() { printf '%s[FAIL]%s %-22s %s\n' "$RED" "$RESET" "$1" "$2"; FAILED=$((FAILED + 1)); FAILURES+=("$1"); }
warn() { printf '%s[WARN]%s %-22s %s\n' "$YELLOW" "$RESET" "$1" "$2"; }

check_http() {   # name url
  local name="$1" url="$2" code
  code=$(curl -s -o /dev/null -m "$TIMEOUT" -w '%{http_code}' "$url" || true)
  if [ "$code" = "200" ]; then ok "$name" "$url"; else fail "$name" "$url -> HTTP ${code:-none}"; fi
}

check_unit() {   # systemd unit
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then ok "$unit" "active"; else fail "$unit" "$(systemctl is-active "$unit" || true)"; fi
}

check_container() {   # docker container
  local c="$1" state
  state=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  if [ "$state" = "running" ]; then ok "docker:$c" "$state"; else fail "docker:$c" "$state"; fi
}

check_disk() {   # mountpoint threshold%
  local mp="$1" max="$2" used
  used=$(df --output=pcent "$mp" | tail -1 | tr -dc '0-9')
  if [ "$used" -ge "$max" ]; then fail "disk:$mp" "${used}% used (>= ${max}%)"
  elif [ "$used" -ge $((max - 10)) ]; then warn "disk:$mp" "${used}% used"
  else ok "disk:$mp" "${used}% used"; fi
}

# name|url pairs; an associative array would lose the order
HTTP_CHECKS=(
  "web|http://localhost/"
  "catalogue|http://localhost:8081/health"
  "user|http://localhost:8082/health"
  "cart|http://localhost:8083/health"
  "shipping|http://localhost:8084/health"
  "payment|http://localhost:8085/health"
  "api-via-nginx|http://localhost/api/catalogue/categories"
)
UNITS=(nginx roboshop-catalogue roboshop-user roboshop-cart roboshop-shipping roboshop-payment roboshop-dispatch)
CONTAINERS=(mongodb mysql redis rabbitmq)

for c in "${CONTAINERS[@]}"; do check_container "$c"; done
for u in "${UNITS[@]}"; do check_unit "$u"; done
for pair in "${HTTP_CHECKS[@]}"; do check_http "${pair%%|*}" "${pair#*|}"; done
check_disk / 85

if [ "$FAILED" -gt 0 ]; then
  echo "${RED}${FAILED} check(s) failed: ${FAILURES[*]}${RESET}"
  command -v logger >/dev/null && logger -t roboshop-healthcheck -p user.err "FAILED: ${FAILURES[*]}"
  exit 1
fi
$QUIET || echo "${GREEN}all checks passed${RESET}"
exit 0
