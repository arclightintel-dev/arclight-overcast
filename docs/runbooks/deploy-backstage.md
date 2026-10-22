# Deploy Backstage

Backstage runs on one EC2 host (`terraform/envs/backstage`, O-012). Overcast never deploys on
merge; a deploy is a manual run of `.github/workflows/deploy-backstage.yml`.

## Inputs

Backstage CI (on its `main` branch, through the `arclight-backstage-prod-ecr-push` role)
publishes, for each commit:

- `arclight/backstage:v1-<sha>` (app and Engine), `arclight/backstage-portal:v3-<sha>` when the
  Portal image changed, `arclight/litestream:v1-0.3.13` (mirror);
- `s3://arclight-backstage-prod-deploy/<sha>/` with `compose.yaml`, `litestream.yml`,
  `.env.example` and `images.json` (`{"app","portal","litestream"}` digests; the last built
  Portal digest is carried forward).

## Deploy

Actions → **Deploy Backstage** → `sha` = the full 40-character commit. The workflow:

1. verifies `images.json` and that every digest exists in ECR;
2. starts the host if it is stopped (waits for a stopping host first) and waits for SSM;
3. runs `/usr/local/sbin/backstage-deploy <sha>` over Run Command, which
   - checks that `login.microsoftonline.com` and `api.anthropic.com` resolve inside the
     allowlist (fails the deploy otherwise: update `entra_cidrs` / `anthropic_cidrs` and apply),
   - copies the bundle into `/srv/backstage/deploy/releases/<sha>/` and writes its digests,
   - pulls the images (root's Docker client, logged out afterwards), switches
     `/srv/backstage/deploy/current`, re-renders secrets, recreates the app and Engine,
   - waits up to 15 minutes for `/ready` (`ready:true`, `recovery_required:false`) and checks
     from Docker that the running app container uses the pinned digest and that its image's
     `org.opencontainers.image.revision` label is `<sha>`;
4. prints the command output and a summary.

`mode`: `normal`; `accept-recovery-required` for cutover and disaster recovery, where the
operator completes recovery with Backstage's tools afterwards; `stage-only` pulls the images and
selects the release but starts nothing, for the smoke deploy and cutover, where one-off commands
must run before the app starts.

The same command can be run by an operator in a Session Manager shell:
`sudo /usr/local/sbin/backstage-deploy <sha>`.

## Rollback

Run the workflow with the previous commit. The five newest release directories stay on the
host, and ECR keeps the ten newest tagged images per repository. A rollback across a database
migration needs Backstage's judgement first: the corpus and control store migrate forward only.

## Secret rotation

Write the new value (`put-secret-value`, no trailing newline), then redeploy the current commit;
the deploy re-renders the secret files and recreates the app and Engine.

## Idle-stop

The host publishes `Busy` every minute: running jobs and Portal runtimes (from the app's
loopback-only `/api/admin/busy`; any failure counts as busy), Portal containers, Session Manager
and Run Command sessions, the hold file `/run/backstage/hold` (honoured six hours), ALB requests
in the last four minutes, and the first hour after boot. Thirty zero minutes stop the instance;
the weekday 07:00 America/New_York schedule or the next deploy starts it.

- Keep the host up during manual work: `sudo install -d -m 0755 /run/backstage && sudo touch /run/backstage/hold`
  (renew within six hours; Session Manager and Run Command sessions also count while open).
- Operator compose commands: `sudo backstage-compose ps`, `logs`, `stop`, `up -d ...` (the current release).
- Keep it up for days (migration week): apply with `-var=idle_stop_enabled=false`.
- A browser tab left open on a stopped host produces ALB 503s, which count toward prod's
  `alb-5xx` alarm (more than 10 in 5 minutes, twice). If that pages at night, raise it.
