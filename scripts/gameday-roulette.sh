#!/usr/bin/env bash
# Picks ONE hidden failure for roboshop-prod. Writes the answer to a file you open only at the end.
set -euo pipefail
NS=roboshop-prod
n=$(( RANDOM % 4 ))
case $n in
  0) kubectl -n $NS set env deploy/catalogue MONGO_URL=mongodb://mongodb-typo:27017/catalogue >/dev/null; a="catalogue MONGO_URL typo";;
  1) kubectl -n $NS scale statefulset redis --replicas=0 >/dev/null; a="redis scaled to 0";;
  2) kubectl -n $NS patch deploy user --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"20Mi"}]' >/dev/null; a="user memory limit 20Mi (OOMKilled)";;
  3) kubectl -n $NS scale deploy shipping --replicas=0 >/dev/null; a="shipping scaled to 0";;
esac
echo "$a" > /tmp/.gameday-answer
echo "Failure injected at $(date -u +%T) UTC. Start your incident. Answer is in /tmp/.gameday-answer (don't peek)."
