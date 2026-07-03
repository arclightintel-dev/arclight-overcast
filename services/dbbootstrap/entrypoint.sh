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

  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: entrypoint.sh [bootstrap|verify|verify-service]" >&2
    exit 2
    ;;
esac
