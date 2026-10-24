# Backstage host: specification, smoke deploy, migration and cutover

Overcast's half of moving Backstage from the owner's PC to AWS (O-012). Backstage's half is its
signed spec, `legacy/podbay` `docs/specs/aws_hosting_spec.md` §8 (`aws/hosting` `fcc39ec`); the
step numbers S1-S5 and C1-C10 below are that section's. Infrastructure:
`terraform/envs/backstage` ([README](../../terraform/envs/backstage/README.md)).

## Host specification (INV-005)

| Item | Value |
|---|---|
| OS | Ubuntu 24.04 LTS (Canonical AMI `ubuntu-noble-24.04-amd64-server-*`), `t3.xlarge`, unlimited credits, us-east-1a private app subnet, no public IP, no key pair |
| Access | Session Manager only (no SSH ingress, no bastion); IMDSv2 required, hop limit 1 |
| Packages (first boot, maintenance egress) | `docker-ce docker-ce-cli containerd.io docker-compose-plugin` from Docker's apt repository; AWS CLI v2 from the official zip; CloudWatch agent from the regional deb; `ca-certificates curl gnupg unzip` |
| Users | No named host account. Containers run as uid/gid **997** (the Portal image's user); host directories are owned by numeric 997. First boot fails if uid 997 is taken, or if gid 997 is a privileged group or has members. On the Ubuntu 24.04 image gid 997 is `crontab` (no members), which is accepted |
| Volumes | root gp3 30 GB (OS, Docker images); data gp3 100 GB at `/srv/backstage`, ext4 label `backstage`, created on first use only, fstab by UUID, `prevent_destroy`, weekly AWS Backup snapshot kept 30 days |
| Paths | `/srv/backstage/{corpus,control,portal,categorization,logs,runtime}` 0750 997:997; `/srv/backstage/deploy` 0750 root (`releases/<sha>/`, `current` symlink); `/etc/backstage` 0700 root: `host.conf` (static), `app.env` and `engine.env` 0600, `categorization.capability` 0400 owned by uid 997, `proxy-endpoints` cache; `/run/backstage/hold` |
| Time | Amazon Time Sync Service `169.254.169.123` (chrony source or timesyncd), no public NTP |
| Docker daemon | default log driver `awslogs` → `/arclight/backstage/<env>/portal` (create-group false, non-blocking), `shutdown-timeout` 120 s; `no-new-privileges` is set per compose service, not as a daemon default (Portal containers are Backstage's to harden) |
| Bridge | `backstage-portal`, subnet `10.255.0.0/24`, interface `br-bkstgportal`, inter-container traffic off |
| Firewall | `DOCKER-USER`: from the bridge, established flows and the proxy endpoints only, then drop; `BACKSTAGE-PORTAL-IN` (from `INPUT -i br-bkstgportal`): replies only, then drop. Reapplied before and after every Docker start |

**Boot sequence (every boot).** `backstage-data` (mount; Docker requires it) and
`backstage-firewall` (Docker requires it) → `docker` (its drop-in reapplies the firewall,
stop timeout 150 s) → `backstage-network` → `backstage-compose` (skipped until a release exists;
renders secrets, then `compose up -d` of the current release) → `backstage-busy.timer`.
First boot runs cloud-init once: uid/gid, mask Docker, write files, install packages, time
source, unmask and start in that order. The app never starts at boot on a fresh host.

**Failure modes.** Data volume missing or unmountable: Docker stays stopped (nothing writes to
the root disk). Firewall cannot get the proxy list: the cached list is used; without one Docker
stays stopped. SSM or Secrets Manager unreachable: `backstage-compose` fails, containers that
dockerd already restarted keep running. Busy publisher failing: no datapoint, no idle-stop.

## Preconditions

- Prod root's interface endpoints applied; the Backstage root applied twice (maintenance egress
  on, then off) and the boot verified (README).
- The owner rotated the proxy credentials committed in Backstage's migration 002 and on the PC
  (D11/D18) before any image push or corpus copy.
- Secrets written: `cookie-key` (the PC's existing key, never a new one), `oidc-client-secret`,
  `anthropic-api-key`, `categorization-capability`. Admin consent and the owner's `admin` role
  assignment on `arclight-backstage` done.
- GitHub environment `backstage` exists, restricted to `main`. Cloudflare record, Full (strict)
  and the WAF skip in place.
- During the whole migration: apply with `-var=idle_stop_enabled=false`, or keep the hold file
  fresh (`sudo install -d -m 0755 /run/backstage && sudo touch /run/backstage/hold`).

All host commands below run in a Session Manager shell (user `ssm-user`), so they use `sudo`:
`/srv/backstage` and `/run/backstage` are root-owned. `sudo backstage-compose ARGS` is
`docker compose` for the current release (`/usr/local/sbin/backstage-compose`).

## Smoke deploy (after Backstage WP1; Litestream stays off)

1. Run the workflow with the WP1 commit and `mode = stage-only`: images pulled, release
   selected, secrets rendered, nothing started (so Litestream never sees the smoke stores).
   Stage-only also sets `/srv/backstage/deploy/no-autostart`, so a reboot or an idle-stop and
   morning start does not start the stack either; containers you start by hand are restarted
   by Docker's own policy, stopped ones are not.
2. S1-S2 as one-off containers (commands confirmed by Backstage at WP1, `aws/hosting` `3dc6bb6`;
   claims go to a mounted path, never `/tmp`, which is tmpfs in the app service):
   ```
   sudo backstage-compose run --rm --no-deps app python -m podbay init-corpus --db /srv/backstage/corpus/podbay.db
   sudo backstage-compose run --rm --no-deps app python -m podbay.identity --control-db /srv/backstage/control/control.sqlite recovery --output /srv/backstage/runtime/recovery.json
   sudo backstage-compose run --rm --no-deps app python -m podbay.identity --control-db /srv/backstage/control/control.sqlite bootstrap --output /srv/backstage/runtime/bootstrap.json
   ```
   Read both claims with `sudo cat`, hand them over out of band, then `sudo rm` them.
   `python -m podbay.identity ... status` prints non-secret facts only.
3. S3 `sudo backstage-compose up -d app engine` (not Litestream); S4 the owner signs in with the
   bootstrap claim.
4. S5 discard:
   ```
   sudo backstage-compose stop
   sudo rm -f /srv/backstage/corpus/podbay.db* /srv/backstage/control/control.sqlite* /srv/backstage/logs/podbay.log
   sudo rm -rf /srv/backstage/categorization/.owner   # a directory; survives an unclean stop
   aws s3 rm --recursive s3://arclight-backstage-prod-litestream/backstage/   # only if Litestream ran
   ```
   A smoke control store must not survive (restore refuses a different `installation_id`).
   Run 2026-10-23 02:31:54Z (smoke on `501f575`, S4 on hotfix `ed8443e`): stores, `.owner` and the smoke log removed;
   the Litestream bucket was empty.

## Cutover

| # | Step | Who |
|---|---|---|
| C1-C3 | Freeze the PC, back up the control store, checkpoint the corpus, upload to `s3://arclight-backstage-prod-migration/` (validation copies under `archive/`) | Owner (Backstage's spec) |
| C4 | Run the workflow with the cutover commit and `mode = stage-only` if it is not already current. Then: `sudo install -d -m 0755 /run/backstage && sudo touch /run/backstage/hold`; `sudo backstage-compose stop`; confirm the smoke stores are gone (`sudo ls -la /srv/backstage/corpus /srv/backstage/control`); `sudo aws s3 sync s3://arclight-backstage-prod-migration/<prefix>/<tree>/ /srv/backstage/<tree>/` for each of the corpus, Portal store and categorization trees (the bucket layout the owner uploaded); `sudo chown -R 997:997 /srv/backstage/corpus /srv/backstage/portal /srv/backstage/categorization`; `sudo backstage-compose run --rm --no-deps app python -c "import sqlite3; print(sqlite3.connect('/srv/backstage/corpus/podbay.db').execute('PRAGMA quick_check').fetchone()[0])"` prints `ok` | Overcast |
| C5 | `sudo backstage-compose run --rm --no-deps app python tools/control_store.py --control-db /srv/backstage/control/control.sqlite restore --from-backup <file>` (`--control-db` is required and goes before the subcommand) (the backup copied under `/srv/backstage/control/`), Litestream stopped | Overcast |
| C6 | `sudo backstage-compose up -d litestream` alone; wait for the first snapshot of both databases (`sudo backstage-compose logs litestream`, `aws s3 ls --recursive s3://arclight-backstage-prod-litestream/backstage/prod/`) | Overcast |
| C7 | `sudo backstage-compose up -d app engine`; `curl -s http://127.0.0.1:8430/ready` shows `recovery_required:true` | Overcast |
| C8-C10 | Reconcile and complete recovery, link-claim before the owner's first sign-in, analysts by role | Backstage, owner, administrator |
| After | Once C8-C10 are done, run the workflow in `normal` mode for the cutover commit: it clears `no-autostart` and verifies the stack. Remove the hold (idle-stop stays off: always on since 2026-10-23); the PC stays stopped and intact for 14 days as warm standby (D15) | Overcast, owner |

## Restore drill (before cutover; verdict condition 4)

On a scratch volume or a stopped project: `litestream restore` both databases with **one**
`-timestamp`, `tools/control_store.py mark-restored`, start, confirm `recovery_required:true`,
time it. Record the RTO and the Litestream lag metric name here; the lag alarm waits for that.
