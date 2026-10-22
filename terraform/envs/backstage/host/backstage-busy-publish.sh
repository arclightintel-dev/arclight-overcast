#!/bin/bash
# backstage-busy.timer, every 60 s: publishes Arclight/Backstage Busy{InstanceId}. The
# idle-stop alarm stops the host after 30 consecutive minutes of Busy = 0.
# Owner decision D16: never stop with a running job or an open Portal. Anything this script
# cannot determine therefore counts as busy, and if the script itself fails no datapoint is
# published, which the alarm treats as missing (no action).
. /usr/local/lib/backstage/common.sh

iid=$(imds instance-id)

# Docker state. If Docker cannot be queried, containers may still be running a job or a
# Portal session, so the unknown state counts as busy.
containers=0
app=0
docker_unknown=0
if timeout 15 docker info >/dev/null 2>&1 &&
  portal=$(timeout 15 docker ps -q --filter network=backstage-portal) &&
  apps=$(timeout 15 docker ps -q --filter label=com.docker.compose.project=backstage \
    --filter label=com.docker.compose.service=app); then
  containers=$(printf '%s' "$portal" | grep -c . || true)
  app=$(printf '%s' "$apps" | grep -c . || true)
else
  docker_unknown=1
fi

# Running jobs and Portal runtimes, from the app on the raw loopback peer (Backstage H10).
jobs=0
if [ "$app" -gt 0 ]; then
  body=$(curl -fsS -m 5 http://127.0.0.1:8430/api/admin/busy 2>/dev/null || true)
  jobs=$(printf '%s' "$body" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(int(d["running_jobs"]) + int(d["portal_runtimes"]))
except Exception:
    print(1)
')
fi

# Operator sessions and Run Command invocations (migration, restore drill, recovery CLI).
sessions=$(pgrep -c -f 'ssm-(session|document)-worker' || true)

# Hold file: touched by the deploy and by runbook steps; honoured for six hours.
hold=0
if [ -n "$(find "$RUN_DIR/hold" -mmin -360 2>/dev/null || true)" ]; then
  hold=1
fi

grace=0
if [ "$(cut -d. -f1 /proc/uptime)" -lt "$(param busy-grace-seconds)" ]; then
  grace=1
fi

# Requests the ALB routed to this target group in the last four minutes.
requests=$("$AWS" cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name RequestCount \
  --dimensions Name=TargetGroup,Value="$(param tg-arn-suffix)" Name=LoadBalancer,Value="$(param alb-arn-suffix)" \
  --start-time "$(date -u -d '-4 minutes' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Sum --query 'sum(Datapoints[].Sum)' --output text 2>/dev/null || echo 1)
requests=${requests%.*}
[[ "$requests" =~ ^[0-9]+$ ]] || requests=1

busy=$((containers + docker_unknown + jobs + sessions + hold + requests + grace))
# PortalContainers feeds the ceiling alarm (more containers than Backstage's cap of 3 means
# leaked or orphaned sessions); published only when Docker answered.
metrics="MetricName=Busy,Dimensions=[{Name=InstanceId,Value=$iid}],Value=$busy,Unit=Count"
if [ "$docker_unknown" -eq 0 ]; then
  metrics="$metrics MetricName=PortalContainers,Dimensions=[{Name=InstanceId,Value=$iid}],Value=$containers,Unit=Count"
fi
# shellcheck disable=SC2086
"$AWS" cloudwatch put-metric-data --namespace Arclight/Backstage --metric-data $metrics
echo "busy=$busy containers=$containers docker_unknown=$docker_unknown jobs=$jobs sessions=$sessions hold=$hold requests=$requests grace=$grace"
