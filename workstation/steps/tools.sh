#!/usr/bin/env bash
# roboshop-infra/workstation/steps/tools.sh  (runs as ec2-user; uses sudo)
# Installs OS packages, Docker CE and pinned CLI tools into /usr/local/bin. Idempotent.
# fast-track kit: core tools are mandatory; "extra" tools only WARN on failure so one renamed release
# asset cannot fail the whole boot. Ansible is installed only when lab.env sets INSTALL_ANSIBLE=yes.
set -euo pipefail
source "$INFRA_DIR/workstation/versions.env"
# shellcheck source=/dev/null
source "$INFRA_DIR/workstation/lab.env"
extra() { "$@" || echo "WARN: optional tool failed: $2 $3 (boot continues; fix versions.env)"; }
BIN=/usr/local/bin

have()  { [ -f "$BIN/.$1-$2" ]; }                          # marker = "installed at this version"
mark()  { sudo rm -f "$BIN/.$1-"*; sudo touch "$BIN/.$1-$2"; }
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

install_bin() {   # install_bin NAME VERSION URL
  have "$1" "$2" && return 0
  echo "installing $1 $2"; fetch "$3" "/tmp/$1" || return 1    # explicit returns: set -e is off inside "extra"/||
  sudo install -m 0755 "/tmp/$1" "$BIN/$1" || return 1; mark "$1" "$2"
}
install_tgz() {   # install_tgz NAME VERSION URL MEMBER   (MEMBER = path inside the archive)
  have "$1" "$2" && return 0
  echo "installing $1 $2"; fetch "$3" "/tmp/$1.tgz" || return 1
  tar -xzf "/tmp/$1.tgz" -C /tmp "$4" || return 1; sudo install -m 0755 "/tmp/$4" "$BIN/$1" || return 1; mark "$1" "$2"
}
install_zip() {   # install_zip NAME VERSION URL MEMBER
  have "$1" "$2" && return 0
  echo "installing $1 $2"; fetch "$3" "/tmp/$1.zip" || return 1
  unzip -o -q "/tmp/$1.zip" "$4" -d /tmp || return 1; sudo install -m 0755 "/tmp/$4" "$BIN/$1" || return 1; mark "$1" "$2"
}

echo "--- OS packages"
sudo dnf install -y -q git jq make unzip tar bash-completion python3-pip dnf-plugins-core

echo "--- Docker CE"
if ! rpm -q docker-ce >/dev/null 2>&1; then
  sudo dnf remove -y -q podman-docker runc 2>/dev/null || true   # conflicts with docker-ce on RHEL
  sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  sudo dnf install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user

echo "--- kernel settings kind needs (many nodes = many inotify watchers)"
printf 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=512\n' | sudo tee /etc/sysctl.d/99-kind.conf >/dev/null
sudo sysctl --system >/dev/null

echo "--- pinned CLIs"
install_bin kubectl   "$KUBECTL_VERSION"   "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install_bin kind      "$KIND_VERSION"      "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
install_tgz helm      "$HELM_VERSION"      "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64/helm
extra install_tgz k9s       "$K9S_VERSION"       "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" k9s
install_bin yq        "$YQ_VERSION"        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
install_tgz trivy     "$TRIVY_VERSION"     "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" trivy
install_bin argocd    "$ARGOCD_VERSION"    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
install_zip terraform "$TERRAFORM_VERSION" "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" terraform

# (phase-02.md Day 17) Ansible - only for the legacy drills (Phase 1-2)
if [ "${INSTALL_ANSIBLE:-no}" = yes ]; then
  # --- Ansible (Phase 2, Day 17) ---
  sudo dnf install -y -q ansible-core python3-pip python3-libselinux acl
  ANSIBLE_PY=$(awk 'NR==1{sub(/^#!/,""); print $1}' "$(command -v ansible)")   # python that runs ansible itself
  for py in /usr/bin/python3 "$ANSIBLE_PY"; do
    "$py" -m pip --version >/dev/null 2>&1 || sudo dnf install -y -q "$(basename "$py")-pip"
    sudo "$py" -m pip install -q --disable-pip-version-check boto3 botocore docker requests
  done
fi

# (phase-06.md Day 62)
extra install_bin cosign "$COSIGN_VERSION" "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"

# (phase-07.md Day 71)
# SonarQube's embedded Elasticsearch needs these on the HOST kernel (kind nodes share it)
printf 'vm.max_map_count=524288\nfs.file-max=131072\n' | sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null
sudo sysctl --system >/dev/null

# (phase-09.md Day 85)
extra install_bin kubectl-argo-rollouts "$ROLLOUTS_VERSION" "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-amd64"

# (phase-12.md Day 109)
extra install_tgz velero "$VELERO_VERSION" \
  "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz" \
  "velero-${VELERO_VERSION}-linux-amd64/velero"

# (phase-12.md Day 115)
extra install_tgz pluto "$PLUTO_VERSION" \
  "https://github.com/FairwindsOps/pluto/releases/download/${PLUTO_VERSION}/pluto_${PLUTO_VERSION#v}_linux_amd64.tar.gz" pluto

# (phase-03 Day 30)
install_bin hadolint "$HADOLINT_VERSION" "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
  || extra install_bin hadolint "$HADOLINT_VERSION" "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-linux-x86_64"
echo "--- shell niceties"
grep -q '# roboshop-lab' ~/.bashrc || cat >> ~/.bashrc <<'EOF'
# roboshop-lab
export PATH=/usr/local/bin:$PATH AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
alias k=kubectl
source <(kubectl completion bash) 2>/dev/null && complete -o default -F __start_kubectl k
EOF

for t in docker kubectl kind helm k9s yq trivy argocd terraform aws; do
  printf '%-10s %s\n' "$t" "$(command -v $t >/dev/null && echo ok || echo MISSING)"
done
