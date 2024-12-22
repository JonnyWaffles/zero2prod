#!/usr/bin/env bash
set -x
set -eo pipefail


if ! [ -x "$(command -v sqlx)" ] ; then
  echo >&2 "Error: sqlx is not installed."
  echo >&2 "Use:"
  echo >&2 " cargo install --version='~0.7' sqlx-cli \
  --no-default-features --features rustls,postgres"
  echo >&2 "to install it."
  exit 1
fi

# Check if a custom user has been set, otherwise default to 'postgres'
SUPERUSER="${SUPERUSER:=postgres}"
# Check if a custom password has been set, otherwise default to 'password'
SUPERUSER_PWD="${POSTGRES_PASSWORD:=password}"
APP_USER="${APP_USER:=app}"
APP_USER_PWD="${APP_USER_PWD:=secret}"
# Check if a custom database name has been set, otherwise default to 'newsletter'
APP_DB_NAME="${POSTGRES_DB:=newsletter}"
# Check if a custom port has been set, otherwise default to '5432'
DB_PORT="${DB_PORT:=5432}"


# Allow to skip Docker if a dockerized Postgres database is already running
if [[ -z "${SKIP_DOCKER}" ]]
  then
  CONTAINER_NAME="postgres"
  # Launch postgres using Docker
  docker run \
  --env POSTGRES_PASSWORD=${SUPERUSER_PWD} \
  --health-cmd="pg_isready -U ${SUPERUSER} || exit 1" \
  --health-interval=1s \
  --health-timeout=5s \
  --health-retries=5 \
  --publish "${DB_PORT}":5432 \
  --detach \
  --name "${CONTAINER_NAME}" \
  postgres -N 1000
  # ^ Increased maximum number of connections for testing purposes

  until [ \
      "$(docker inspect -f "{{.State.Health.Status}}" ${CONTAINER_NAME})" == \
      "healthy" \
      ]; do
        >&2 echo "Postgres is still unavailable - sleeping"
        sleep 1
  done

    # Create the application user
    CREATE_QUERY="CREATE USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';"
    docker exec -it "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -c "${CREATE_QUERY}"
    # Grant create db privileges to the app user
    GRANT_QUERY="ALTER USER ${APP_USER} CREATEDB;"
    docker exec -it "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -c "${GRANT_QUERY}"
fi

>&2 echo "Postgres is up and running on port ${DB_PORT} - running migrations now!"


# Create the application database
DATABASE_URL=postgres://${APP_USER}:${APP_USER_PWD}@localhost:${DB_PORT}/${APP_DB_NAME}
export DATABASE_URL
sqlx database create
sqlx migrate run
