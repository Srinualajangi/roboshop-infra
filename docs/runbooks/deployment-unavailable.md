# Runbook: RoboshopDeploymentUnavailable (critical)

**Meaning:** a RoboShop Deployment has 0 available replicas. Users see errors for that feature.

## First 5 minutes (mitigate before you diagnose)
1. Which one? `kubectl -n <ns> get deploy,pods -l app.kubernetes.io/name=<deployment>`
2. What changed? `argocd app history <service>-<env>` and `git log -5` in roboshop-gitops.
3. If a recent deploy caused it: roll back with `git revert <promotion commit>` and sync (Day 55).
## Diagnose
- `kubectl -n <ns> describe pod <pod>` → Events (ImagePullBackOff? Pending? OOMKilled?)
- `kubectl -n <ns> logs <pod> --previous`
- Grafana → RoboShop · Golden signals (env) → Loki `{namespace="<ns>", app="<deployment>"}`
## Close
- Confirm the alert resolved in Slack, add a line to the incident log, postmortem if users were affected > 5 min.
