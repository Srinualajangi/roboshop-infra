# terraform/20-workstation/terraform.tfvars
owner = "Srinu Alajangi"
gh_user = "Srinualajangi"

# fast-track kit: pick the size for the profiles you boot (workstation/lab.env LAB_PROFILES)
#   core / "obs"          -> m6i.2xlarge (8 vCPU / 32 GiB, the default)  ~$0.12-0.20/h Spot
#   "obs sec ci" (all)    -> r6i.2xlarge (8 vCPU / 64 GiB)               ~$0.15-0.25/h Spot
# instance_type         = "r6i.2xlarge"
# root_volume_gb        = 120        # image builds + every add-on image fit comfortably
# auto_shutdown_minutes = 240        # long interview-revision session (30-480)
