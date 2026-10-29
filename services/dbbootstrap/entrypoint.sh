#!/bin/sh
set -e

MODE="${1:-bootstrap}"
ENV="${ENVIRONMENT:-staging}"

case "$MODE" in
  bootstrap)
    echo "Starting database bootstrap (env=$ENV)..."

    psql -v ON_ERROR_STOP=1 \
      -v env="$ENV" \
      -v core_pw="$CORE_PW" -v sf_pw="$SF_PW" -v podbay_pw="$PODBAY_PW" -v nf_pw="$NF_PW" \
      -f /bootstrap.sql

    for svc in core shuttleforge podbay nerfherder; do
      db="${svc}_${ENV}"
      role="$db"
      echo "Setting up schema permissions for $db..."
      psql -v ON_ERROR_STOP=1 -d "$db" <<EOSQL
ALTER SCHEMA public OWNER TO $role;
GRANT ALL ON SCHEMA public TO $role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $role;
EOSQL
    done

    echo "Bootstrap complete."
    ;;

  verify)
    echo "Verifying database state (master credentials, env=$ENV)..."
    psql -v ON_ERROR_STOP=1 -c '\l' -c '\du'
    for svc in core shuttleforge podbay nerfherder; do
      db="${svc}_${ENV}"
      echo "Testing $db (as master)..."
      psql -v ON_ERROR_STOP=1 -d "$db" -c 'CREATE TABLE _verify_test(id int); DROP TABLE _verify_test;'
    done
    echo "Master verification complete."
    ;;

  verify-service)
    echo "Verifying service role database access (env=$ENV)..."
    for url_var in CORE_DATABASE_URL SF_DATABASE_URL PODBAY_DATABASE_URL NF_DATABASE_URL; do
      eval url=\$$url_var
      if [ -z "$url" ]; then
        echo "FAIL: $url_var not set" >&2
        exit 1
      fi
      echo "Testing $url_var..."
      psql -v ON_ERROR_STOP=1 "$url" -c 'CREATE TABLE _verify_svc(id int); DROP TABLE _verify_svc;'
    done
    echo "Service role verification complete."
    ;;

  sf-app-role)
    # ShuttleForge's DML-only runtime role (O-4). Grants follow SF's reference
    # (scripts/local_appliance.py at ad2668b). Touches only shuttleforge_<env>; never run
    # `bootstrap` for this, it resets every service role's password. Idempotent: run it
    # before the first migration and again after each one (alembic_version stays read-only).
    db="shuttleforge_${ENV}"
    owner="$db"
    app="shuttleforge_app_${ENV}"
    # SF_OWNER_URL is ShuttleForge's own schema-owner URL (db-url-migration), the single
    # source of the owner credential: the bootstrap temporary (SF_PW) was spent in July.
    if [ -z "$SF_OWNER_URL" ] || [ -z "$SF_APP_PW" ]; then
      echo "FAIL: SF_OWNER_URL and SF_APP_PW must both be set" >&2
      exit 1
    fi
    # SF's URLs are postgresql+asyncpg://; libpq needs postgresql:// and no driver query.
    owner_url=$(printf '%s' "$SF_OWNER_URL" | sed -e 's#^postgresql+asyncpg://#postgresql://#' -e 's#?.*$##')
    who=$(PGSSLMODE=require psql "$owner_url" -tA -v ON_ERROR_STOP=1 -c 'SELECT current_user || chr(124) || current_database()')
    if [ "$who" != "$owner|$db" ]; then
      echo "FAIL: SF_OWNER_URL must connect as $owner to $db" >&2
      exit 1
    fi

    # Created once with SF_APP_PW; a re-run never resets the password, so db-url stays valid.
    echo "Creating role $app if absent (master)..."
    psql -v ON_ERROR_STOP=1 -v app="$app" -v app_pw="$SF_APP_PW" <<'EOSQL'
SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app')
  THEN format('ALTER ROLE %I LOGIN NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 16', :'app')
  ELSE format('CREATE ROLE %I LOGIN NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 16 PASSWORD %L', :'app', :'app_pw')
END \gexec
EOSQL

    # Database and schema grants, and default privileges FOR ROLE owner, must be issued by
    # the owner: the RDS master is not a superuser and does not own shuttleforge_<env>.
    echo "Granting $app on $db (as $owner)..."
    PGSSLMODE=require psql "$owner_url" -v ON_ERROR_STOP=1 \
      -v db="$db" -v owner="$owner" -v app="$app" <<'EOSQL'
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db', :'app') \gexec
REVOKE ALL ON SCHEMA public FROM PUBLIC;
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'app') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', :'owner', :'app') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO %I', :'owner', :'app') \gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I', :'app') \gexec
SELECT format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', :'app') \gexec
SELECT format('REVOKE INSERT, UPDATE, DELETE ON public.alembic_version FROM %I', :'app')
  WHERE to_regclass('public.alembic_version') IS NOT NULL \gexec
EOSQL
    echo "sf-app-role complete."
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: entrypoint.sh [bootstrap|verify|verify-service|sf-app-role]" >&2
    exit 2
    ;;
esac
