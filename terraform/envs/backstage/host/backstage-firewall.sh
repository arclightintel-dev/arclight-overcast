#!/bin/bash
# backstage-firewall.service (before Docker) and Docker's ExecStartPost (after it): Portal
# containers on the backstage-portal bridge may open connections only to the proxy
# endpoints, and nothing on the host. Idempotent: creates its chains if absent, then
# flushes and refills them. The proxy list comes from SSM (proxy-endpoints); the last good
# list is cached so an SSM outage at boot does not leave Docker stopped.
. /usr/local/lib/backstage/common.sh

cache=/etc/backstage/proxy-endpoints
if endpoints=$(param proxy-endpoints 2>/dev/null); then
  printf '%s\n' "$endpoints" >"$cache.tmp"
  mv -f "$cache.tmp" "$cache"
elif [ -s "$cache" ]; then
  log "SSM unavailable: using the last known proxy endpoint list"
  endpoints=$(cat "$cache")
else
  die "no proxy endpoint list (SSM unavailable and no cached copy)"
fi
for ep in $endpoints; do
  [[ "$ep" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ ]] || die "malformed entry in the proxy endpoint list"
done

br="$BRIDGE_IFNAME"
ipt() { iptables -w 10 "$@"; }

# Forwarded traffic from the bridge: established flows, the proxies, nothing else.
ipt -N DOCKER-USER 2>/dev/null || true
ipt -F DOCKER-USER
ipt -A DOCKER-USER -i "$br" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for ep in $endpoints; do
  ipt -A DOCKER-USER -i "$br" -d "${ep%:*}/32" -p tcp --dport "${ep##*:}" -j ACCEPT
done
ipt -A DOCKER-USER -i "$br" -j DROP
ipt -A DOCKER-USER -j RETURN

# Traffic from the bridge to the host itself (port 8430, sshd, anything): replies only.
ipt -N BACKSTAGE-PORTAL-IN 2>/dev/null || true
ipt -F BACKSTAGE-PORTAL-IN
ipt -A BACKSTAGE-PORTAL-IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ipt -A BACKSTAGE-PORTAL-IN -j DROP
ipt -C INPUT -i "$br" -j BACKSTAGE-PORTAL-IN 2>/dev/null || ipt -I INPUT 1 -i "$br" -j BACKSTAGE-PORTAL-IN

log "applied: $(wc -w <<<"$endpoints") proxy endpoints allowed from $br"
