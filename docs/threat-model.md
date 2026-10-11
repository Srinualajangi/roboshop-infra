# RoboShop threat model (lab)
Owner: <you> · Last reviewed: <date> · Review trigger: any new component, external integration or IAM change.

## System and trust boundaries
<paste the diagram from Day 89 Step 1>

## STRIDE-lite table
<paste the table from Day 89 Step 2>

## Accepted risks (lab only — would not be accepted in production)
- IMDS hop limit 3: every pod in kind can use the workstation instance role. Mitigation: that role is least-privilege (ECR roboshop/*, SSM /roboshop/*). Production: EKS Pod Identity/IRSA, hop limit 1.
- Single account for everything (no dev/prod account separation). Production: AWS Organizations, an account per environment, SCPs.
- Public GitHub repos: anyone can read the manifests. Mitigation: zero secrets in Git, enforced by gitleaks.
- In-cluster data stores without TLS or auth (mongodb, redis). Production: managed services with TLS + IAM/auth.

## Open items
- [ ] Day 90 Kyverno  - [ ] Day 91 signed images  - [ ] Day 92 runtime scanning  - [ ] Day 93 rotation  - [ ] Day 94 AWS baseline
