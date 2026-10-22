#!/bin/bash
# backstage-deploy <40-hex sha> [--accept-recovery-required | --stage-only]
# Run as root by SSM Run Command from .github/workflows/deploy-backstage.yml (or by an
# operator over Session Manager). Copies the release bundle for <sha> into its own
# directory, pulls the pinned images while the current release keeps running, switches the
# current release, starts it and checks the app. Rollback: run it again with the previous
# sha; the five newest release directories are kept on disk.
# --accept-recovery-required: accept /ready with recovery_required:true (cutover and DR,
#   where the operator completes recovery afterwards).
# --stage-only: stop after selecting the release and rendering secrets; start nothing. For
#   the smoke deploy and cutover, where one-off commands (init-corpus, control-store
#   restore) must run before the app starts (docs/runbooks/migrate-backstage.md). It also
#   sets /srv/backstage/deploy/no-autostart, so a reboot does not start the stack either;
#   the next normal deploy (or the operator, once cutover is verified) removes it.
. /usr/local/lib/backstage/common.sh

sha="${1:-}"
mode="${2:-}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "usage: backstage-deploy <40-hex sha> [--accept-recovery-required | --stage-only]"
case "$mode" in
  "" | --accept-recovery-required | --stage-only) ;;
  *) die "unknown option: $mode" ;;
esac

install -d -m 0755 "$RUN_DIR"
touch "$RUN_DIR/hold"
registry=""
stage=""
cleanup() {
  rm -f "$RUN_DIR/hold"
  if [ -n "$registry" ]; then docker logout "$registry" >/dev/null 2>&1 || true; fi
  if [ -n "$stage" ] && [ -d "$stage" ]; then rm -rf "$stage"; fi
}
trap cleanup EXIT

# 1. The sign-in and categorization hosts still resolve inside the security-group allowlist.
check_allowlisted() {
  local addrs
  addrs=$(getent ahostsv4 "$1" | awk '{print $1}' | sort -u)
  [ -n "$addrs" ] || die "$1 does not resolve"
  # shellcheck disable=SC2086
  python3 - "$2" $addrs <<'PY' || die "$1 resolves outside the allowlist; update the root's entra_cidrs or anthropic_cidrs and apply first"
import ipaddress, sys
nets = [ipaddress.ip_network(c) for c in sys.argv[1].split()]
outside = [a for a in sys.argv[2:] if not any(ipaddress.ip_address(a) in n for n in nets)]
if outside:
    print("outside the allowlist: " + " ".join(outside), file=sys.stderr)
    sys.exit(1)
PY
}
check_allowlisted login.microsoftonline.com "$(param entra-cidrs)"
check_allowlisted api.anthropic.com "$(param anthropic-cidrs)"

# 2. The bundle into a staging directory. Not "s3 sync": it skips same-size files, which
# would leave the previous release's images.json in place. Everything that can fail (copy,
# digests, .env, pulls) happens in staging, so a failed deploy never touches the release
# that is running, including a redeploy of the same commit after a secret rotation.
rel="$DEPLOY_DIR/releases/$sha"
stage=$(mktemp -d "$DEPLOY_DIR/releases/.stage.XXXXXX")
"$AWS" s3 cp --recursive --only-show-errors "s3://$(param deploy-bucket)/$sha/" "$stage/"
for f in compose.yaml litestream.yml images.json; do
  [ -f "$stage/$f" ] || die "the bundle for $sha has no $f"
done
python3 - "$stage/images.json" >"$stage/digests.env" <<'PY'
import json, re, sys
images = json.load(open(sys.argv[1]))
for key, var in (("app", "BACKSTAGE_APP_DIGEST"), ("portal", "BACKSTAGE_PORTAL_DIGEST"),
                 ("litestream", "BACKSTAGE_LITESTREAM_DIGEST")):
    digest = str(images[key]).rsplit("sha256:", 1)[-1]
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        sys.exit(f"images.json: {key} is not a sha256 digest")
    print(f"{var}={digest}")
PY
/usr/local/sbin/backstage-render-env "$stage"

# 3. Pull the pinned images (root's Docker client only; logged out on exit).
registry=$(param ecr-registry)
"$AWS" ecr get-login-password | docker login --username AWS --password-stdin "$registry" >/dev/null
compose "$stage" pull --quiet
compose "$stage" --profile prepull pull --quiet

# The staged release is complete: replace the release directory with it. Running containers
# keep their bind mounts across the rename; the old directory is removed only afterwards.
chmod 0750 "$stage"
old=""
if [ -e "$rel" ]; then
  old="$DEPLOY_DIR/releases/.old.$sha.$$"
  mv "$rel" "$old"
fi
mv "$stage" "$rel"
stage=""
if [ -n "$old" ]; then rm -rf "$old"; fi

# 4. Switch the current release and start it. Secrets are re-read so a rotated value takes
# effect; app and Engine are recreated explicitly because env_file contents are not part of
# the container configuration compose compares.
ln -sfn "releases/$sha" "$DEPLOY_DIR/current.next"
mv -T "$DEPLOY_DIR/current.next" "$DEPLOY_DIR/current"
/usr/local/sbin/backstage-render-secrets
if [ "$mode" = --stage-only ]; then
  touch "$DEPLOY_DIR/no-autostart"
  log "staged $sha as the current release; nothing started, and boot autostart is off (--stage-only)"
  exit 0
fi
rm -f "$DEPLOY_DIR/no-autostart"
compose "$rel" up -d --force-recreate --no-deps app engine
compose "$rel" up -d --remove-orphans

# 5. Ready, and running the requested code.
ready_ok() {
  local body
  body=$(curl -fsS -m 5 http://127.0.0.1:8430/ready 2>/dev/null) || return 1
  printf '%s' "$body" | ACCEPT="$mode" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
recovery_ok = d.get("recovery_required") is False or os.environ.get("ACCEPT") == "--accept-recovery-required"
sys.exit(0 if d.get("ready") is True and recovery_ok else 1)'
}
deadline=$((SECONDS + 900))
until ready_ok; do
  [ "$SECONDS" -lt "$deadline" ] || die "/ready did not report ready within 15 minutes"
  sleep 10
done
# The running app container is the pinned image of this commit. Read from Docker, not from
# the app over loopback: Backstage trusts forwarded headers only from the ALB subnets, so a
# loopback request cannot present the public scheme (and needs no such trust).
app_id=$(compose "$rel" ps -q app)
[ -n "$app_id" ] || die "no running app container"
app_image=$(docker inspect --format '{{.Image}}' "$app_id")
want_digest=$(sed -n 's/^BACKSTAGE_APP_DIGEST=//p' "$rel/digests.env")
docker image inspect --format '{{json .RepoDigests}}' "$app_image" | grep -q "sha256:$want_digest" ||
  die "the app container does not run the pinned image sha256:$want_digest"
revision=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$app_image")
[ "$revision" = "$sha" ] || die "the app image carries revision $revision, not $sha"

# 6. Keep the five newest releases as rollback targets (never the current one), and only the
# images they reference: ECR's lifecycle policy prunes the registry, not this disk. Never a
# blanket "image prune -a": the Portal image is unused by any container between sessions.
current=$(readlink -f "$DEPLOY_DIR/current")
find "$DEPLOY_DIR/releases" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%T@ %p\n' |
  sort -rn | tail -n +6 | cut -d' ' -f2- | while read -r old; do
  [ "$(readlink -f "$old")" = "$current" ] || rm -rf "$old"
done
keep=$(cat "$DEPLOY_DIR"/releases/*/digests.env 2>/dev/null | cut -d= -f2 | sort -u)
docker image ls --digests --format '{{.Repository}} {{.Digest}}' |
  awk -v r="$registry/arclight/" 'index($1, r) == 1 && $2 ~ /^sha256:/' |
  while read -r repo digest; do
    grep -qx "${digest#sha256:}" <<<"$keep" || docker image rm "$repo@$digest" >/dev/null 2>&1 || true
  done
log "deployed $sha"
