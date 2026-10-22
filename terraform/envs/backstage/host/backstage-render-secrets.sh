#!/bin/bash
# backstage-render-secrets: the four Backstage secrets into files the compose project reads
# (app.env, engine.env: root 0600) or bind-mounts (categorization.capability: owner uid 997,
# 0400, so the app and Engine containers read it as owner, not through group 997). Run before
# every start and every deploy, so a rotated value takes effect on the next deploy.
# Values are never printed, logged or passed as command arguments (printf is a builtin).
. /usr/local/lib/backstage/common.sh
umask 077

secret() {
  local value attempt
  for attempt in 1 2 3 4 5; do
    if value=$("$AWS" secretsmanager get-secret-value --secret-id "arclight/backstage/$ENVIRONMENT/$1" \
      --query SecretString --output text 2>/dev/null) && [ -n "$value" ] && [ "$value" != None ]; then
      case "$value" in
        *[[:space:]]* | *'$'* | *'"'* | *"'"* | *'\'*)
          die "secret $1 contains whitespace, a quote, a backslash or a dollar sign; rewrite it without them"
          ;;
      esac
      printf '%s' "$value"
      return 0
    fi
    sleep 10
  done
  die "secret $1 is unavailable (no value yet, or no access)"
}

# write PATH MODE OWNER: content from stdin, replaced atomically.
write() {
  local tmp
  tmp=$(mktemp "$(dirname "$1")/.render.XXXXXX")
  cat >"$tmp"
  chown "$3" "$tmp"
  chmod "$2" "$tmp"
  mv -f "$tmp" "$1"
}

cookie=$(secret cookie-key)
oidc=$(secret oidc-client-secret)
anthropic=$(secret anthropic-api-key)
capability=$(secret categorization-capability)

install -d -m 0700 /etc/backstage
printf 'PODBAY_COOKIE_KEY=%s\nPODBAY_OIDC_CLIENT_SECRET=%s\n' "$cookie" "$oidc" | write /etc/backstage/app.env 0600 root:root
printf 'PODBAY_ANTHROPIC_API_KEY=%s\n' "$anthropic" | write /etc/backstage/engine.env 0600 root:root
printf '%s' "$capability" | write /etc/backstage/categorization.capability 0400 "$APP_UID:root"
log "rendered app.env, engine.env and categorization.capability"
