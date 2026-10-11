#!/usr/bin/env bash
# Breaks ONE random thing in roboshop-qa. Answer is stored base64-encoded in ~/.chaos/answer.
# Reveal after your investigation:  base64 -d ~/.chaos/answer
set -euo pipefail
NS=roboshop-qa
mkdir -p ~/.chaos
pick=$(( RANDOM % 6 ))
one_of() { local arr=("$@"); echo "${arr[RANDOM % ${#arr[@]}]}"; }
case $pick in
  0) s=$(one_of catalogue user cart shipping payment)
     kubectl -n $NS scale deploy/$s --replicas=0 >/dev/null
     ans="scaled deploy/$s to 0 replicas" ;;
  1) kubectl -n $NS set env deploy/catalogue MONGO_URL=mongodb://mongodb:27018/catalogue >/dev/null
     ans="catalogue MONGO_URL points at wrong port 27018" ;;
  2) s=$(one_of cart catalogue user)
     kubectl -n $NS set resources deploy/$s --limits=cpu=15m --requests=cpu=15m >/dev/null
     ans="CPU-starved deploy/$s (limit 15m) -> latency" ;;
  3) np=$(kubectl -n $NS get netpol -o name | grep -v -i deny | shuf -n1 || true)
     if [ -n "$np" ]; then kubectl -n $NS delete "$np" >/dev/null; ans="deleted NetworkPolicy $np (an allow rule)";
     else kubectl -n $NS scale deploy/cart --replicas=0 >/dev/null; ans="scaled deploy/cart to 0 (no netpol found)"; fi ;;
  4) kubectl -n $NS scale statefulset/redis --replicas=0 >/dev/null 2>&1 || kubectl -n $NS scale deploy/redis --replicas=0 >/dev/null
     ans="redis scaled to 0 (cart + user sessions fail)" ;;
  5) kubectl -n $NS set env deploy/payment AMQP_HOST=rabbitmq-nope >/dev/null
     ans="payment AMQP_HOST points at a non-existent host" ;;
esac
echo "$ans | broken at $(date +%T)" | base64 > ~/.chaos/answer
echo "💥 Something in $NS is now broken ($(date +%T)). Start traffic and go find it."
