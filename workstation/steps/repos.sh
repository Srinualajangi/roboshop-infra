#!/usr/bin/env bash
# roboshop-infra/workstation/steps/repos.sh  (runs as ec2-user)
# Clones/pulls your repos into ~/work. Pull = HTTPS (public, no creds). Push = SSH via laptop agent forwarding.
set -euo pipefail
git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.ff only
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keyscan -t ed25519 github.com 2>/dev/null >> ~/.ssh/known_hosts

mkdir -p ~/work && cd ~/work
for r in roboshop-infra roboshop-app roboshop-gitops jenkins-shared-library; do
  if [ -d "$r/.git" ]; then
    git -C "$r" pull -q || echo "WARN: could not pull $r"
  elif git ls-remote "https://github.com/$GH_USER/$r.git" >/dev/null 2>&1; then
    git clone -q "https://github.com/$GH_USER/$r.git"
  else
    echo "skip $r (repo does not exist yet)"; continue
  fi
  git -C "$r" remote set-url --push origin "git@github.com:$GH_USER/$r.git"
  echo "ok  ~/work/$r"
done
