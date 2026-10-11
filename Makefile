# roboshop-infra/Makefile  - run on your LAPTOP (WSL / macOS / Linux).  `make help` lists the targets.
# fast-track kit version: Day 7 targets + Phase 11 EKS targets + fast-track helpers (up-full, preflight, ...).
#
# HOW TO READ THIS FILE (new to make? read 10-make-explained.md in the fast-track folder):
#   name: ## text      <- a "target". You run it with:  make name
#   <TAB>command       <- the shell commands that target runs (recipe lines MUST start with a TAB)
#   VAR := value       <- a variable, used as $(VAR). "?=" means "only if you did not set it already"
#   @command           <- run the command without printing it first
#   $$                 <- a literal "$" for the shell (make itself uses single $)

# run every recipe with bash (not sh)
SHELL := /bin/bash
# which AWS CLI profile (your SSO login) every command uses
export AWS_PROFILE ?= roboshop
export AWS_REGION  ?= us-east-1
# your 12-digit account id (empty = not logged in)
ACCOUNT := $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
# the S3 bucket that stores Terraform state (created once by 00-bootstrap)
BUCKET  := roboshop-tfstate-$(ACCOUNT)
# which Terraform folder plan/apply/destroy work on; override: make plan LAYER=10-foundation
LAYER   ?= 20-workstation
# "terraform, but run inside terraform/<LAYER>"
TF       = terraform -chdir=terraform/$(LAYER)
# shortcut for the daily workstation layer
WS       = terraform -chdir=terraform/20-workstation

# "everything on" settings used by make up-full: 64 GiB box, bigger disk, all add-on profiles, the sonar step.
# TF_VAR_<name>=value is how you hand a value to a Terraform variable without editing any file.
FULL_VARS = TF_VAR_instance_type=r6i.2xlarge TF_VAR_root_volume_gb=120 \
            TF_VAR_lab_profiles="obs sec ci" TF_VAR_lab_steps="tools repos kind argocd root-app sonar"

# .PHONY = "these are command names, not files to build" (stops make getting confused by a file called e.g. "up")
.PHONY: help init plan apply destroy up up-full down wait status connect tunnel ssh-config extend cost fmt validate \
        eks-up eks-down eks-plan preflight timed-up timed-up-full log ui

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# ---- Terraform basics (any layer) ------------------------------------------------------------
init: ## terraform init for LAYER (default 20-workstation)
	@test -n "$(ACCOUNT)" || { echo "Not logged in: aws sso login --profile $(AWS_PROFILE)"; exit 1; }
	$(TF) init -input=false -reconfigure -backend-config="bucket=$(BUCKET)" >/dev/null

plan: init ## terraform plan for LAYER=...  (shows what WOULD change, changes nothing)
	$(TF) plan -input=false

apply: init ## terraform apply for LAYER=... (asks you to type yes)
	$(TF) apply -input=false

destroy: init ## terraform destroy for LAYER=... (refuses 00-* and 10-*: those are never destroyed)
	@case "$(LAYER)" in 00-*|10-*) echo "Refusing to destroy persistent layer $(LAYER)"; exit 1;; esac
	$(TF) destroy -input=false

# ---- The daily workstation -------------------------------------------------------------------
up: ## create today's workstation (settings from lab.env + terraform.tfvars) and wait for bootstrap
	@$(MAKE) --no-print-directory init LAYER=20-workstation
	$(WS) apply -input=false -auto-approve
	@$(MAKE) --no-print-directory ssh-config
	@$(MAKE) --no-print-directory wait

up-full: ## like "up" but EVERYTHING on for this boot: r6i.2xlarge 64 GiB, 120 GB disk, obs+sec+ci (~25-30 min)
	@echo "Full lab: r6i.2xlarge (~\$$0.15-0.25/h Spot), profiles obs sec ci. No files are changed."
	@$(MAKE) --no-print-directory init LAYER=20-workstation
	$(FULL_VARS) $(WS) apply -input=false -auto-approve
	@$(MAKE) --no-print-directory ssh-config
	@WAIT_MIN=45 $(MAKE) --no-print-directory wait

down: ## destroy today's workstation, then list anything still costing money
	@$(MAKE) --no-print-directory init LAYER=20-workstation
	$(WS) destroy -input=false -auto-approve
	@bash scripts/leftovers.sh

wait: ## wait until the workstation reports ready (reads SSM /roboshop/lab/status)
	@bash scripts/wait-ready.sh

status: ## show anything billable that is still running
	@bash scripts/leftovers.sh

connect: ## SSM shell on the workstation (no SSH needed)
	aws ssm start-session --target $$($(WS) output -raw instance_id)

ssh-config: ## refresh the roboshop-lab entry in ~/.ssh/config (the instance id changes every boot)
	@bash scripts/ssh-config.sh

tunnel: ## forward laptop :8080 -> workstation :80 (keep this terminal open)
	@echo "Open http://dev.roboshop.test:8080 (argocd/grafana/... .roboshop.test:8080). Ctrl-C to stop."
	ssh -N -L 8080:localhost:80 roboshop-lab

extend: ## push the auto-shutdown 60 minutes into the future
	ssh roboshop-lab 'sudo shutdown -c; sudo shutdown -h +60 "roboshop lab auto-shutdown (extended)"'

cost: ## month-to-date cost by service (Cost Explorer API: ~$0.01 per call)
	@aws ce get-cost-and-usage --time-period Start=$$(date +%Y-%m-01),End=$$(date -d tomorrow +%F) \
	  --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
	  --query 'ResultsByTime[0].Groups[?to_number(Metrics.UnblendedCost.Amount) > `0.01`].[Keys[0],Metrics.UnblendedCost.Amount]' --output table

fmt: ## terraform fmt for all layers (re-formats .tf files)
	terraform fmt -recursive terraform

validate: ## terraform validate every layer (syntax/type check, no AWS calls)
	@for d in terraform/*/; do echo "== $$d"; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; done

# ---- fast-track helpers ----------------------------------------------------------------------
preflight: ## check laptop tools, SSO login, AWS layers, SSM params, placeholders, GitHub (30 s, read-only)
	@bash scripts/ft-preflight.sh

timed-up: ## make up with a stopwatch (write the number down - interviewers love it)
	@s=$$(date +%s); $(MAKE) --no-print-directory up && echo "⏱  make up took $$(( ($$(date +%s)-s)/60 )) min $$(( ($$(date +%s)-s)%60 )) s"

timed-up-full: ## make up-full with a stopwatch
	@s=$$(date +%s); $(MAKE) --no-print-directory up-full && echo "⏱  make up-full took $$(( ($$(date +%s)-s)/60 )) min $$(( ($$(date +%s)-s)%60 )) s"

log: ## follow the bootstrap log on the workstation
	ssh roboshop-lab 'sudo tail -n 60 -f /var/log/roboshop-bootstrap.log'

ui: ## print the Argo CD admin password and every URL to open through the tunnel
	@ssh roboshop-lab 'echo "argocd admin password: $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} 2>/dev/null | base64 -d)"'
	@for h in dev qa prod argocd grafana prometheus alertmanager rollouts jenkins sonar; do echo "  http://$$h.roboshop.test:8080"; done

# ---- Phase 11: EKS sprint (laptop) -----------------------------------------------------------
# your public IP: the only address allowed to the EKS API
MYIP = $(shell curl -fsS https://checkip.amazonaws.com)
EKS_VARS = TF_VAR_admin_cidrs='["$(MYIP)/32"]'

eks-up: ## create VPC + EKS + add-ons for today's EKS session (~18-20 min)
	$(MAKE) init LAYER=30-network
	terraform -chdir=terraform/30-network apply -input=false -auto-approve
	$(MAKE) init LAYER=40-eks
	$(EKS_VARS) terraform -chdir=terraform/40-eks apply -input=false -auto-approve
	aws eks update-kubeconfig --name roboshop-eks --region us-east-1 --alias roboshop-eks
	bash scripts/eks-addons.sh

eks-down: ## delete k8s-created AWS resources, then destroy 50 -> 40 -> 30 (~15 min)
	-bash scripts/eks-predestroy.sh
	-[ -d terraform/50-data ] && $(MAKE) init LAYER=50-data && terraform -chdir=terraform/50-data destroy -input=false -auto-approve
	$(MAKE) init LAYER=40-eks
	$(EKS_VARS) terraform -chdir=terraform/40-eks destroy -input=false -auto-approve
	$(MAKE) init LAYER=30-network
	terraform -chdir=terraform/30-network destroy -input=false -auto-approve
	-kubectl config delete-context roboshop-eks
	bash scripts/leftovers.sh

eks-plan: ## plan 40-eks (network must exist)
	$(MAKE) init LAYER=40-eks
	$(EKS_VARS) terraform -chdir=terraform/40-eks plan -input=false
