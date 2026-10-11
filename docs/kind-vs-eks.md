# kind (daily lab) vs Amazon EKS (sprint): what actually changed

| Area | kind on the workstation | EKS sprint | Evidence / number |
|---|---|---|---|
| Networking | kindnet overlay, pod IPs 10.244.x, 110 pods/node | VPC CNI, pod IPs from app /20 subnets, ENI-limited | pod 10.40.x → eni-..., maxPods <29> on m6i.large |
| Ingress / LB | Traefik NodePort 30080 → host :80 → SSH tunnel | AWS Load Balancer Controller → ALB, target-type ip, IngressGroup | ALB created in <n> min; targets = pod IPs |
| Storage | local-path on the node's disk | EBS CSI gp3, AZ-bound volumes, WaitForFirstConsumer | vol-..., deleted only if PVC deleted first |
| Identity for pods | instance role via IMDS hop limit 3 (lab trick) | Pod Identity per controller, IMDS blocked (hop 1) | curl to IMDS timed out; ESO role in CloudTrail |
| Human access | client cert in kubeconfig | IAM SSO + access entries (no aws-auth) | `kubectl auth whoami` |
| Nodes | docker containers, fixed 3 workers | managed node group (Spot) + Karpenter | Karpenter node Ready in <n> s |
| Upgrades | recreate cluster with new node image | in-place CP → add-ons → rolling node group | CP <n> min, nodes <n> min, <n> failed requests |
| Data | StatefulSets in-cluster | RDS MySQL, data subnets, SG-to-SG | password never in state |
| Cost | ~$0.15/h workstation Spot | ~$0.35/h (EKS $0.10 + NAT + nodes + ALB) | sprint total $<n> |
| Blast radius | everything on one VM | 3-AZ control plane, nodes in 2 AZs, single NAT = AZ-a SPOF | |
| Teardown risk | none (terminate VM) | orphaned ALBs/EBS/EC2 block VPC delete → pre-destroy script | |

## What I would change for a real company
- account per environment, private API endpoint, NAT per AZ, WAF + ACM in front of the ALB, Multi-AZ RDS, ...
## Mistakes I made and fixed
- ...
