#!/usr/bin/env bash
# fast-track kit: break-fix drills for interview revision. Run ON THE WORKSTATION.
#   ft-break.sh list                 all drills (id, level, what breaks)
#   ft-break.sh <id>                 inject one drill (you know what it is - practise the diagnosis)
#   ft-break.sh random               BLIND drill in qa: you don't know what broke (answer hidden)
#   ft-break.sh hint  [<id>]         the diagnosis commands for a drill (or the hidden one)
#   ft-break.sh fix   [<id>]         the correct fix (GitOps-style where Git is the source of truth)
#   ft-break.sh reveal               show what the blind drill broke
#   ft-break.sh reset                put qa + prod back to exactly what Git says (DR sync), undo node/DNS breaks
# Why qa? dev has Argo CD self-heal: it would "fix" your break before you find it (that is drill 'selfheal').
set -uo pipefail
NS=${FT_NS:-roboshop-qa}; E=${NS#roboshop-}
ST=~/.ft-drill; mkdir -p "$ST"
k() { kubectl -n "$NS" "$@"; }
sync_app() {   # sync_app <argocd-app> [replace]  == the Sync button (no argocd CLI login needed)
  # A normal sync restores fields Git manages, but does NOT remove fields someone ADDED by hand that Git never sets
  # (an extra command, nodeSelector, CPU limit...). For those, "replace" sends the whole object = Git, nothing else.
  local opts='["ServerSideApply=true"]'; [ "${2:-}" = replace ] && opts='["Replace=true"]'
  kubectl -n argocd patch application "$1" --type merge -p \
    "{\"operation\":{\"initiatedBy\":{\"username\":\"ft-break\"},\"sync\":{\"prune\":true,\"syncOptions\":$opts}}}" >/dev/null \
    && echo "   sync requested: $1 ${2:-} (watch: kubectl -n argocd get application $1 -w)"
}
REG=$(aws sts get-caller-identity --query Account --output text 2>/dev/null).dkr.ecr.us-east-1.amazonaws.com

# id | level | title        (level: 1 = first week of a job, 2 = solid mid-level, 3 = senior/SRE)
DRILLS="
crashloop|1|a service CrashLoopBackOff (bad start command)
imagepull|1|ImagePullBackOff (a tag that does not exist in ECR)
pending-quota|2|pods Pending: namespace ResourceQuota exceeded
pending-selector|1|pods Pending: nodeSelector matches no node
oom|1|OOMKilled (memory limit too small for the JVM)
no-endpoints|2|Service has no endpoints (selector typo) -> 502 in the shop
wrong-config|2|pods all green but users get errors (wrong MONGO_URL port)
db-down|2|a data store is gone (mongodb scaled to 0)
secret-missing|2|CreateContainerConfigError: Secret deleted (ESO re-creates it)
cpu-starve|3|everything 'works' but is slow (CPU limit 15m)
dns|3|cluster DNS outage (CoreDNS scaled to 0) - cluster-wide
netpol-deny|3|default-deny NetworkPolicy without a DNS allow -> EAI_AGAIN
node-down|3|a worker node dies (docker stop roboshop-worker2)
argocd-repo|3|GitOps is blind: argocd-repo-server down
selfheal|1|DEMO (dev): drift is reverted by Argo CD self-heal in seconds
drift|2|DEMO (prod): manual change shows OutOfSync and stays (no self-heal in prod)
pss|1|DEMO: Pod Security 'restricted' rejects privileged/root pods
canary|3|GUIDED (prod, needs LAB_PROFILES=obs): bad release auto-aborted by the canary analysis
"
list() { echo "$DRILLS" | awk -F'|' 'NF{printf "  %-17s L%s  %s\n",$1,$2,$3}'; }

brk() {
  case "$1" in
    crashloop)  k patch deploy user --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["node","does-not-exist.js"]}]' ;;
    imagepull)  k set image deploy/cart cart="$REG/roboshop/cart:does-not-exist" ;;
    pending-quota) k scale deploy shipping --replicas=12 ;;
    pending-selector) k patch deploy ratings -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"genral"}}}}}' ;;
    oom)        k set resources deploy/shipping --requests=memory=96Mi --limits=memory=96Mi ;;
    no-endpoints) k patch svc cart -p '{"spec":{"selector":{"app":"carts"}}}' ;;
    wrong-config) k set env deploy/catalogue MONGO_URL=mongodb://mongodb:27018/catalogue ;;
    db-down)    k scale sts mongodb --replicas=0 ;;
    secret-missing) k delete secret payment-amqp && k rollout restart deploy/payment ;;
    cpu-starve) k set resources deploy/catalogue --limits=cpu=15m --requests=cpu=15m ;;
    dns)        kubectl -n kube-system scale deploy coredns --replicas=0 ;;
    netpol-deny) cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: ft-default-deny, namespace: $NS }
spec: { podSelector: {}, policyTypes: [Ingress, Egress] }
EOF
                ;;
    node-down)  docker stop roboshop-worker2 ;;
    argocd-repo) kubectl -n argocd scale deploy argocd-repo-server --replicas=0 ;;
    selfheal)   date +%T; kubectl -n roboshop-dev scale deploy cart --replicas=4
                echo "   watch Argo CD put it back:  kubectl -n roboshop-dev get deploy cart -w" ;;
    drift)      kubectl -n roboshop-prod scale deploy cart --replicas=3
                echo "   now: kubectl -n argocd get application cart-prod   (OutOfSync, and it STAYS - prod is manual sync)" ;;
    pss)        kubectl -n roboshop-dev run evil --image=public.ecr.aws/docker/library/busybox:1.36 --privileged -- sleep 3600
                kubectl -n roboshop-dev run rooty --image=public.ecr.aws/docker/library/busybox:1.36 -- sleep 3600
                echo "   both must be Forbidden. Proof inside a real pod:"
                kubectl -n roboshop-dev exec deploy/catalogue -- sh -c 'id; touch /evil 2>&1; grep -E "CapEff|NoNewPrivs|Seccomp" /proc/1/status' ;;
    canary)     cat <<'EOF'
   GUIDED drill (Git is the change channel, so you do the commit):
   1. workstation, inside ~/work/roboshop-gitops:
        yq -i '.rollout.successRate = {"enabled": true, "prometheus": "http://kps-prometheus.monitoring.svc:9090"} |
               .rollout.canary = {"analysis": {"templates": [{"templateName": "catalogue-success-rate"}], "startingStep": 1,
                                  "args": [{"name": "service-regex", "value": "roboshop-prod-catalogue.*"}]},
                                  "steps": [{"setWeight": 20}, {"pause": {"duration": "3m"}}, {"setWeight": 50},
                                            {"pause": {"duration": "2m"}}, {"setWeight": 100}]}' envs/prod/catalogue.yaml
        git commit -am "feat(prod): catalogue canary gated by success rate" ; publish it ; then sync catalogue-prod
   2. traffic:   kubectl run trafficgen --image=curlimages/curl --restart=Never -- sh -c \
                 'while true; do curl -s -o /dev/null -H "Host: prod.roboshop.test" http://traefik.traefik.svc.cluster.local/api/catalogue/products; sleep 0.2; done'
   3. the BAD release: yq -i '.env.MONGO_URL = "mongodb://mongodb-typo:27017/catalogue"' envs/prod/catalogue.yaml
        git commit -am "release(prod): catalogue config change (deliberately bad)" ; publish ; sync catalogue-prod
   4. watch it abort by itself:  kubectl argo rollouts -n roboshop-prod get rollout catalogue --watch
   5. RIGHT fix: git revert HEAD ; publish ; sync.   (WRONG fix: 'kubectl argo rollouts undo' -> Git and cluster disagree)
   6. clean up: kubectl delete pod trafficgen
   Note: the analysis query uses Traefik's service label; check it once with
         curl -s localhost/... or in Prometheus: count by (service) (traefik_service_requests_total)
EOF
                return 0 ;;
    *) echo "unknown drill '$1'. ft-break.sh list"; exit 1 ;;
  esac
}

hint() {
  echo "Diagnosis loop: get -> describe -> events -> logs --previous -> dependencies -> fix the SOURCE OF TRUTH"
  case "$1" in
    crashloop) echo "  kubectl -n $NS get pods -l app=user ; kubectl -n $NS logs deploy/user --previous | tail ; kubectl -n $NS describe pod -l app=user | grep -A3 'Last State'" ;;
    imagepull) echo "  kubectl -n $NS describe pod -l app=cart | tail -8   (401 = auth, 'not found' = tag/digest, i/o timeout = network)" ;;
    pending-quota) echo "  kubectl -n $NS get events --sort-by=.lastTimestamp | grep -i quota ; kubectl -n $NS describe quota" ;;
    pending-selector) echo "  kubectl -n $NS describe pod -l app=ratings | tail -5 ; kubectl get nodes --show-labels | grep pool" ;;
    oom) echo "  kubectl -n $NS describe pod -l app=shipping | grep -A5 'Last State'   (OOMKilled, exit 137)" ;;
    no-endpoints) echo "  kubectl -n $NS get endpointslices -l kubernetes.io/service-name=cart ; kubectl -n $NS get svc cart -o jsonpath='{.spec.selector}' ; kubectl -n $NS get pods -l app=cart --show-labels" ;;
    wrong-config) echo "  curl -s -H 'Host: $E.roboshop.test' localhost/api/catalogue/health  (mongo:false) ; kubectl -n $NS logs deploy/catalogue | tail ; kubectl -n argocd get application catalogue-$E (OutOfSync!) " ;;
    db-down) echo "  kubectl -n $NS get sts ; kubectl -n $NS get endpointslices -l kubernetes.io/service-name=catalogue (readiness removed the pods?) ; logs of catalogue" ;;
    secret-missing) echo "  kubectl -n $NS get pods | grep -v Running ; kubectl -n $NS describe pod -l app=payment | grep -i secret ; kubectl -n $NS get externalsecret payment-amqp" ;;
    cpu-starve) echo "  kubectl top pods -n $NS ; kubectl -n $NS exec deploy/catalogue -- cat /sys/fs/cgroup/cpu.stat | grep throttled ; time curl -s -H 'Host: $E.roboshop.test' localhost/api/catalogue/products >/dev/null" ;;
    dns) echo "  kubectl -n $NS logs deploy/cart --tail=5 (EAI_AGAIN) ; kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns" ;;
    netpol-deny) echo "  kubectl -n $NS exec deploy/cart -- sh -c 'getent hosts redis || echo DNS-FAIL' ; kubectl -n $NS get networkpolicy" ;;
    node-down) echo "  kubectl get nodes -w ; kubectl get pods -A -o wide | grep worker2 ; why do StatefulSet pods NOT move? (local PV node affinity)" ;;
    argocd-repo) echo "  kubectl -n argocd get applications | head (Unknown / ComparisonError) ; kubectl -n argocd get pods ; kubectl -n argocd logs deploy/argocd-application-controller --tail=20 | grep -i repo" ;;
    *) echo "  no hint for '$1'" ;;
  esac
}

fix() {
  case "$1" in
    crashloop) sync_app user-$E replace ;;   # the drift ADDED a field Git does not set
    imagepull) sync_app cart-$E ;;
    pending-quota) sync_app shipping-$E ;;
    pending-selector) sync_app ratings-$E replace ;;   # the drift ADDED a field Git does not set
    oom) sync_app shipping-$E ;;
    no-endpoints) sync_app cart-$E ;;
    wrong-config) sync_app catalogue-$E ;;
    db-down) sync_app mongodb-$E ;;
    secret-missing) k annotate externalsecret payment-amqp force-sync="$(date +%s)" --overwrite && echo "   ESO re-created the Secret; the pod starts by itself" ;;
    cpu-starve) sync_app catalogue-$E replace ;;   # the drift ADDED a field Git does not set
    dns) kubectl -n kube-system scale deploy coredns --replicas=2 && kubectl -n kube-system rollout status deploy/coredns ;;
    netpol-deny) kubectl -n "$NS" delete networkpolicy ft-default-deny ;;
    node-down) docker start roboshop-worker2 && kubectl wait --for=condition=Ready node/roboshop-worker2 --timeout=120s ;;
    argocd-repo) kubectl -n argocd scale deploy argocd-repo-server --replicas=1 ;;
    selfheal) echo "   nothing to fix - Argo CD already did it (that is the point)" ;;
    drift) sync_app cart-prod ;;
    pss) kubectl -n roboshop-dev delete pod evil rooty --ignore-not-found ;;
    canary) echo "   git revert the bad commit, publish, sync catalogue-prod (see: ft-break.sh canary)" ;;
    *) echo "unknown drill '$1'"; exit 1 ;;
  esac
  echo "   then prove it: scripts/ft-smoke.sh $E"
}

cmd=${1:-list}
case "$cmd" in
  list) echo "Drills (default namespace $NS; FT_NS=roboshop-prod to change):"; list ;;
  random)
    ids=$(echo "$DRILLS" | awk -F'|' 'NF && $3 !~ /^(DEMO|GUIDED)/ && $1!="node-down" && $1!="dns" && $1!="argocd-repo" {print $1}')
    pick=$(echo "$ids" | shuf -n1)
    echo "$pick" | base64 > "$ST/answer"; date +%s > "$ST/started"
    brk "$pick" >/dev/null 2>&1
    echo "💥 Something in $NS is broken ($(date +%T)). Open http://$E.roboshop.test:8080, then investigate."
    echo "   Stuck after 10 min?  ft-break.sh hint     Done?  ft-break.sh reveal" ;;
  reveal) [ -f "$ST/answer" ] || { echo "no blind drill running"; exit 1; }
    a=$(base64 -d "$ST/answer"); s=$(( $(date +%s) - $(cat "$ST/started") ))
    echo "It was: $a  ($(echo "$DRILLS" | awk -F'|' -v a="$a" '$1==a{print $3}'))"; echo "Time to diagnose: $((s/60))m$((s%60))s"
    echo "Fix with: ft-break.sh fix $a" ;;
  hint) id=${2:-$( [ -f "$ST/answer" ] && base64 -d "$ST/answer")}; hint "$id" ;;
  fix)  id=${2:-$( [ -f "$ST/answer" ] && base64 -d "$ST/answer")}; fix "$id"; rm -f "$ST/answer" ;;
  reset)
    kubectl -n kube-system scale deploy coredns --replicas=2 >/dev/null 2>&1
    docker start roboshop-worker2 >/dev/null 2>&1
    kubectl -n argocd scale deploy argocd-repo-server --replicas=1 >/dev/null 2>&1
    for n in roboshop-qa roboshop-prod; do kubectl -n $n delete networkpolicy ft-default-deny --ignore-not-found >/dev/null; done
    for app in $(kubectl -n argocd get applications -l 'env in (qa,prod)' -o name); do sync_app "${app#*/}"; done
    rm -f "$ST/answer"; echo "reset requested - run scripts/ft-smoke.sh --wait" ;;
  *)
    echo "$DRILLS" | grep -q "^$cmd|" || { echo "unknown drill '$cmd'"; list; exit 1; }
    echo "💥 drill '$cmd' in $NS: $(echo "$DRILLS" | awk -F'|' -v a="$cmd" '$1==a{print $3}')"
    brk "$cmd"; echo "   diagnose it, then: ft-break.sh hint $cmd  /  ft-break.sh fix $cmd" ;;
esac
