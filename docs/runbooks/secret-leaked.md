# Runbook: a secret was pushed to GitHub
Severity: SEV-2 by default (SEV-1 if it is an AWS key or a prod credential). Assume it is already stolen —
public GitHub is scraped by bots within minutes.

## 1. Contain (first 15 min) — rotate BEFORE you clean history
- AWS access key: `aws iam update-access-key --status Inactive` then delete; check `aws sts get-caller-identity` attempts in CloudTrail.
  (In this lab there should be NO access keys at all — SSO/OIDC/instance role only.)
- GitHub token/PAT: revoke in GitHub settings → Developer settings.
- DB / app password: rotate with the dual-password procedure (Day 93), update SSM, let ESO + Reloader roll pods.
## 2. Assess blast radius
- What could this credential do? (IAM policy / DB grants). Since when was it public? (commit time)
- CloudTrail: `aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<AKIA...> --max-results 50`
- Unusual regions, new IAM users/keys, EC2 launches (crypto mining), S3 GetObject spikes. GuardDuty findings if enabled.
## 3. Eradicate
- Remove from history only AFTER rotation: `git filter-repo --replace-text expressions.txt` (or BFG), force-push,
  ask GitHub support to purge cached views if needed; forks/clones may still have it — that's why rotation comes first.
## 4. Recover & learn
- Confirm the old credential fails. Close the incident. Postmortem: why did pre-commit/CI gitleaks not stop it? Add the pattern.
