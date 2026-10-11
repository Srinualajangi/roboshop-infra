# Postmortem: <short title>   (blameless)

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Environment | qa (lab drill) / prod |
| Severity | SEV1 (users blocked) / SEV2 (degraded) / SEV3 (no user impact) |
| Duration | start → resolved (HH:MM) |
| Detected by | alert <name> / user report / dashboard |
| TTD / TTM / TTR | detect: _ min · mitigate: _ min · resolve: _ min |
| Author / IC | |

## Summary
Two or three sentences a manager understands: what users saw, for how long, what fixed it.

## Impact
Which user journeys broke (browse / login / cart / checkout), % of requests failed (from the SLO dashboard), error budget consumed (minutes).

## Timeline (all times local)
- HH:MM  change / trigger happened
- HH:MM  alert fired (name)
- HH:MM  acknowledged, investigation started
- HH:MM  key finding (which signal showed it: metric / log / trace)
- HH:MM  mitigation applied (what exactly)
- HH:MM  recovered (how verified)

## Root cause and trigger
Trigger = what started it. Root cause = the condition in the system that allowed it. Use 5 whys:
1. Why did checkout fail? ...
2. Why ...? ...
(stop at a cause you can fix with a system change, not "a person made a mistake")

## What went well
## What went badly / where we got lucky
## Action items
| Action | Type (prevent / detect / mitigate) | Owner | Due | Ticket |
|---|---|---|---|---|
| e.g. alert on payment queue consumers = 0 | detect | me | +7d | |

## Interview value
One line: the STAR story this gives you and the numbers (TTD, TTR, budget burned).
