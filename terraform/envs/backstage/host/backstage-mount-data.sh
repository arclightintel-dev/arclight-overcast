#!/bin/bash
# backstage-data.service: wait for the data volume, create its filesystem on first use only,
# mount it at /srv/backstage and create the directories the compose project expects.
# Failure leaves Docker stopped (the Docker drop-in requires this unit): nothing is ever
# written to the root disk in place of the data volume.
. /usr/local/lib/backstage/common.sh

link="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID}"
for _ in $(seq 1 150); do
  [ -e "$link" ] && break
  udevadm settle --timeout=2 || true
  sleep 2
done
[ -e "$link" ] || die "data volume ${DATA_VOLUME_ID} is not attached after 300 s"
dev=$(readlink -f "$link")

if [ -z "$(blkid -o value -s TYPE "$dev" || true)" ]; then
  log "data volume has no filesystem: creating ext4 (first use only)"
  mkfs.ext4 -q -L backstage "$dev"
fi
uuid=$(blkid -o value -s UUID "$dev")
[ -n "$uuid" ] || die "data volume has no filesystem UUID"

mkdir -p /srv/backstage
if ! grep -q "^UUID=$uuid /srv/backstage " /etc/fstab; then
  sed -i '\| /srv/backstage |d' /etc/fstab
  echo "UUID=$uuid /srv/backstage ext4 defaults,nofail,x-systemd.device-timeout=90 0 2" >>/etc/fstab
fi
mountpoint -q /srv/backstage || mount /srv/backstage

for d in corpus control portal categorization logs runtime; do
  install -d -m 0750 -o "$APP_UID" -g "$APP_UID" "/srv/backstage/$d"
done
install -d -m 0750 -o root -g root "$DEPLOY_DIR" "$DEPLOY_DIR/releases"
log "mounted /srv/backstage (UUID $uuid)"
