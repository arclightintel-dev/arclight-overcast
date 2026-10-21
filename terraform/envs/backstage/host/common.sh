# Sourced by every Backstage host script (installed at /usr/local/lib/backstage/common.sh).
# Static per-instance values come from /etc/backstage/host.conf, written once by user-data.
# Everything that can change is read from SSM Parameter Store at run time, so changing it
# never replaces the host. Nothing here reads, prints or logs a secret.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/backstage/host.conf
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

AWS=/usr/local/bin/aws
RUN_DIR=/run/backstage
DEPLOY_DIR=/srv/backstage/deploy

log() { printf '%s: %s\n' "${0##*/}" "$*" >&2; }
die() {
  log "FATAL: $*"
  exit 1
}

# param NAME: value of $SSM_PREFIX/NAME, retried; a persistent failure fails the caller.
param() {
  local value attempt
  for attempt in 1 2 3 4 5; do
    if value=$("$AWS" ssm get-parameter --name "$SSM_PREFIX/$1" --query Parameter.Value --output text 2>/dev/null); then
      printf '%s' "$value"
      return 0
    fi
    sleep 3
  done
  die "SSM parameter $SSM_PREFIX/$1 is unavailable"
}

# imds PATH: one instance-metadata value over IMDSv2.
imds() {
  local token
  token=$(curl -fsS -m 5 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
  curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/$1"
}

# compose DIR ARGS...: the Backstage compose project in a release directory (real path, so
# a changed bind-mount source in a new release is a changed container configuration).
compose() {
  local dir="$1"
  shift
  docker compose --project-directory "$dir" -f "$dir/compose.yaml" "$@"
}
