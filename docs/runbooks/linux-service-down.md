# Runbook: RoboShop service down (legacy / systemd host)

**Alert / symptom:** a page or API path fails (502/504 from nginx, empty product list, checkout error).
**Severity guide:** checkout or login broken = SEV2 (customer impact); ratings only = SEV4.
**Owner:** platform on-call. Escalate to: app team after 30 min without mitigation.

## 1. Confirm (2 min)
    curl -s -o /dev/null -w '%{http_code}\n' localhost/                      # web tier
    for p in 8081 8082 8083 8084 8085; do printf "%s " $p; curl -s -o /dev/null -w '%{http_code}\n' localhost:$p/health; done
    systemctl --failed
Which port fails = which service: 8081 catalogue, 8082 user, 8083 cart, 8084 shipping, 8085 payment, 8086 ratings.

## 2. What changed? (1 min)
    sudo journalctl --since "1 hour ago" | grep -iE "Started|Stopped|Reloaded" | tail
    ls -lt /etc/systemd/system/roboshop-* /etc/nginx/conf.d/ | head
    last -n 5

## 3. Diagnose the failing service (outside → in)
    systemctl status roboshop-<svc> --no-pager ; systemctl show roboshop-<svc> -p NRestarts
    journalctl -u roboshop-<svc> -n 50 --no-pager
    sudo ss -tlnp | grep <port>
| Log says | Likely cause | Fix |
|---|---|---|
| Cannot find module / No such file | bad ExecStart or WorkingDirectory | fix unit, daemon-reload, restart |
| EADDRINUSE / Address already in use | port conflict | `ss -tlnp 'sport = :<port>'`, stop the intruder |
| EACCES / Permission denied | owner/mode, or SELinux | `namei -l <path>`, `ausearch -m avc -ts recent` |
| No space left on device | disk full | `df -h`, `du -xh`, `lsof +L1`; truncate, rotate |
| ECONNREFUSED / ENOTFOUND to a dependency | datastore down or bad host/DNS | `docker ps`, `getent hosts <name>`, check Environment= |
| nginx 502 + "13: Permission denied" | SELinux httpd_can_network_connect | `setsebool -P httpd_can_network_connect 1` |

## 4. Mitigate
Capture logs first: `journalctl -u roboshop-<svc> --since "30 min ago" > /tmp/<svc>-incident.log`
Then: `sudo systemctl restart roboshop-<svc>`; if a datastore: `docker restart <name>`.

## 5. Verify and close
Re-run step 1, place a test order in the browser, and note timeline + root cause for the postmortem.
