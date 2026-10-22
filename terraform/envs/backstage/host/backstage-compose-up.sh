#!/bin/bash
# backstage-compose.service at boot: start the current release. Skipped by the unit's
# ConditionPathExists until the first deploy has selected a release, so a fresh host never
# fetches secrets that do not exist yet. Containers dockerd already restarted are left as
# they are (up -d recreates only what changed).
# After an instance replacement the data volume still holds "current" but the new root
# volume has no images, so compose pulls the pinned digests: log root's Docker client in to
# ECR first (instance profile), and out again afterwards.
. /usr/local/lib/backstage/common.sh

rel=$(readlink -f "$DEPLOY_DIR/current")
/usr/local/sbin/backstage-render-env "$rel"

registry=$(param ecr-registry)
trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT
# Neither step is fatal: with ECR unreachable, a host that still has its images starts from
# them; "up" fails only if an image is genuinely missing.
"$AWS" ecr get-login-password | docker login --username AWS --password-stdin "$registry" >/dev/null ||
  log "ECR login failed; starting from local images"
compose "$rel" --profile prepull pull --quiet --ignore-pull-failures || log "pre-pull incomplete"
compose "$rel" up -d --remove-orphans
log "started release ${rel##*/}"
