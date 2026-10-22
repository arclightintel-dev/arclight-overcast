#!/bin/bash
# backstage-network.service: the user-defined bridge the app attaches Portal containers to
# (PODBAY_PORTAL_NETWORK). Fixed subnet and interface name so the firewall can name it;
# inter-container traffic off. Docker persists the network, so later boots are a no-op.
. /usr/local/lib/backstage/common.sh

if docker network inspect backstage-portal >/dev/null 2>&1; then
  exit 0
fi
docker network create --driver bridge --subnet "$PORTAL_SUBNET" \
  -o com.docker.network.bridge.name="$BRIDGE_IFNAME" \
  -o com.docker.network.bridge.enable_icc=false \
  backstage-portal >/dev/null
log "created backstage-portal ($PORTAL_SUBNET on $BRIDGE_IFNAME)"
