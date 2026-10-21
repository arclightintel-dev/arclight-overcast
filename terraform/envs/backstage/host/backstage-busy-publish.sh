#!/bin/bash
# backstage-busy.timer, every 60 s: publishes Arclight/Backstage Busy{InstanceId}. The
# idle-stop alarm stops the host after 30 consecutive minutes of Busy = 0.
# Owner decision D16: never stop with a running job or an open Portal. Anything this script
# cannot determine therefore counts as busy, and if the script itself fails no datapoint is
# published, which the alarm treats as missing (no action).
. /usr/local/lib/backstage/common.sh

iid=$(imds instance-id)

containers=0
app=0
if docker info >/dev/null 2>&1; then
  containers=$(docker ps -q --filter network=backstage-portal | wc -l)
  app=$(docker ps -q --filter label=com.docker.compose.project=backstage \
    --filter label=com.docker.compose.service=app | wc -l)
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

busy=$((containers + jobs + sessions + hold + requests + grace))
"$AWS" cloudwatch put-metric-data --namespace Arclight/Backstage \
  --metric-data "MetricName=Busy,Dimensions=[{Name=InstanceId,Value=$iid}],Value=$busy,Unit=Count"
echo "busy=$busy containers=$containers jobs=$jobs sessions=$sessions hold=$hold requests=$requests grace=$grace"
