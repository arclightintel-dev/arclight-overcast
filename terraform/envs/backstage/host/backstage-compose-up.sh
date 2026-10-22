#!/bin/bash
# backstage-compose.service at boot: start the current release. Skipped by the unit's
# ConditionPathExists until the first deploy has selected a release, so a fresh host never
# fetches secrets that do not exist yet. Containers dockerd already restarted are left as
# they are (up -d recreates only what changed).
. /usr/local/lib/backstage/common.sh

rel=$(readlink -f "$DEPLOY_DIR/current")
/usr/local/sbin/backstage-render-env "$rel"
compose "$rel" up -d --remove-orphans
log "started release ${rel##*/}"
