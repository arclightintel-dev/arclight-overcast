#!/bin/bash
# backstage-compose ARGS...: docker compose for the current Backstage release, for operators in
# a Session Manager shell (run with sudo: the release directory is root-only). Examples:
#   sudo backstage-compose ps
#   sudo backstage-compose stop
#   sudo backstage-compose up -d litestream
#   sudo backstage-compose run --rm --no-deps app python tools/control_store.py ...
. /usr/local/lib/backstage/common.sh

[ "$(id -u)" -eq 0 ] || die "run with sudo"
[ -e "$DEPLOY_DIR/current" ] || die "no release selected yet (run a deploy, mode stage-only, first)"
compose "$(readlink -f "$DEPLOY_DIR/current")" "$@"
