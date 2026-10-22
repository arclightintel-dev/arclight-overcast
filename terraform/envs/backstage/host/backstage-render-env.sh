#!/bin/bash
# backstage-render-env [RELEASE_DIR]: writes the non-secret compose variables (.env) for a
# release directory (default: the current release). Image digests come from the release's
# digests.env, which the deploy writes from the bundle's images.json; the rest from SSM.
. /usr/local/lib/backstage/common.sh

dir=$(readlink -f "${1:-$DEPLOY_DIR/current}")
[ -f "$dir/digests.env" ] || die "$dir has no digests.env"

docker_gid=$(getent group docker | cut -d: -f3)
[ -n "$docker_gid" ] || die "the docker group does not exist"
ecr=$(param ecr-registry)
cidrs=$(param alb-subnet-cidrs)
bucket=$(param litestream-bucket)
client=$(param oidc-client-id)

tmp=$(mktemp "$dir/.env.XXXXXX")
{
  printf 'BACKSTAGE_ECR=%s\n' "$ecr"
  printf 'DOCKER_GID=%s\n' "$docker_gid"
  printf 'ALB_SUBNET_CIDRS=%s\n' "$cidrs"
  printf 'BACKSTAGE_LITESTREAM_BUCKET=%s\n' "$bucket"
  printf 'BACKSTAGE_OIDC_CLIENT_ID=%s\n' "$client"
  cat "$dir/digests.env"
} >"$tmp"
chmod 0640 "$tmp"
mv -f "$tmp" "$dir/.env"
