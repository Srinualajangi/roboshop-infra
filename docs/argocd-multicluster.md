Hub-and-spoke (central Argo CD on kind managing EKS):
1. 40-eks: workstation_access = true   (access entry: role roboshop-workstation → AmazonEKSClusterAdminPolicy)
2. 40-eks: admin_cidrs += workstation public IP /32  (hub must reach the spoke API; in a company: private connectivity via TGW)
3. workstation: aws eks update-kubeconfig --name roboshop-eks --alias eks-prod
4. workstation: argocd cluster add eks-prod --name eks-prod
      → creates ServiceAccount argocd-manager + ClusterRoleBinding on EKS, stores a bearer token as a Secret on kind
      (better: an Argo CD cluster Secret with awsAuthConfig {clusterName, roleARN} so Argo uses IAM, not a static token)
5. ApplicationSet with a clusters{} generator (label env=prod) → destination.server = EKS endpoint
Trade-offs: one UI/RBAC/audit  vs  hub = blast radius + needs network + credentials to every cluster
