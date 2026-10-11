# Postmortem: <title, e.g. "Cart 5xx in prod due to Redis unavailable"> (game day)
Date: · Severity: SEV-2 · Duration: __ min · Author: me · Status: final

## Summary (3 sentences a manager understands)
## Impact
Users affected / requests failed (from Grafana: error-rate panel screenshot) · SLO budget consumed: __%
## Timeline (UTC)
| Time | Event |
|---|---|
| 14:05 | failure injected |
| 14:08 | alert X fired (MTTD 3 min) |
| 14:15 | IC declared SEV-2 |
| 14:22 | mitigated by argocd sync |
| 14:25 | resolved, alert cleared (MTTR 20 min) |
## Root cause & 5 whys
1. Why did checkout fail? Redis had 0 replicas.
2. Why did that cause 5xx not a degraded cart? cart has no fallback / circuit breaker.
3. Why was 0 replicas possible? Manual change allowed in prod (no RBAC/drift guard).
4. Why wasn't it reverted automatically? prod selfHeal=false by design (manual sync).
5. Why did detection take 3 min? Alert `for: 2m` + scrape interval.
## What went well / what went badly / where we got lucky
## Action items
| Action | Type (prevent/detect/mitigate) | Owner | Due |
|---|---|---|---|
| Alert on statefulset replicas available < desired in prod | detect | me | +7d |
| Restrict `scale` verb in prod RBAC to break-glass group | prevent | me | +14d |
