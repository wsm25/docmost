#!/usr/bin/env bash

set -euo pipefail

SYNC_ENABLED="${SYNC_ENABLED:-true}"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-86400}"
SYNC_RETENTION_DAYS="${SYNC_RETENTION_DAYS:-7}"
SYNC_RCLONE_REMOTE="${SYNC_RCLONE_REMOTE:-oss:db}"
SYNC_STORAGE_ENABLED="${SYNC_STORAGE_ENABLED:-true}"
SYNC_STORAGE_REMOTE="${SYNC_STORAGE_REMOTE:-oss:storage}"
POSTGRES_HOST="${POSTGRES_HOST:-db}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

log() {
  printf '[sync] %s\n' "$*"
}

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    log "missing required env: ${key}"
    exit 1
  fi
}

cleanup_local() {
  find /backup -type f -name 'db-*.bin' -mtime "+${SYNC_RETENTION_DAYS}" -delete
}

cleanup_remote_db() {
  log "cleaning remote db backups older than ${SYNC_RETENTION_DAYS} days"
  rclone delete "${SYNC_RCLONE_REMOTE}" \
    --min-age "${SYNC_RETENTION_DAYS}d" \
    --include "db-*.bin"
}

sync_storage() {
  if [[ "${SYNC_STORAGE_ENABLED}" != "true" ]]; then
    return
  fi

  log "syncing storage to ${SYNC_STORAGE_REMOTE}"
  rclone sync /data/docmost-storage "${SYNC_STORAGE_REMOTE}"
}

upload_backup() {
  local ts filename raw_file encrypted_file remote_path
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  filename="db-${ts}.bin"
  raw_file="/backup/db-${ts}.sql.gz"
  encrypted_file="/backup/${filename}"
  remote_path="${SYNC_RCLONE_REMOTE%/}/${filename}"

  log "creating pg_dump for ${POSTGRES_DB}"
  pg_dump \
    --host "${POSTGRES_HOST}" \
    --port "${POSTGRES_PORT}" \
    --username "${POSTGRES_USER}" \
    --dbname "${POSTGRES_DB}" \
    --clean \
    --if-exists \
    | gzip -c > "${raw_file}"

  log "encrypting backup"
  openssl enc -aes-256-cbc -pbkdf2 -salt \
    -in "${raw_file}" \
    -out "${encrypted_file}" \
    -pass "pass:${SYNC_PASSPHRASE}"

  rm -f "${raw_file}"

  log "uploading to ${remote_path}"
  rclone copyto "${encrypted_file}" "${remote_path}"
}

main() {
  if [[ "${SYNC_ENABLED}" != "true" ]]; then
    log "sync disabled; sleeping"
    while true; do
      sleep "${SYNC_INTERVAL_SECONDS}"
    done
  fi

  require_env POSTGRES_DB
  require_env POSTGRES_USER
  require_env POSTGRES_PASSWORD
  require_env SYNC_PASSPHRASE
  require_env SYNC_RCLONE_REMOTE
  if [[ "${SYNC_STORAGE_ENABLED}" == "true" ]]; then
    require_env SYNC_STORAGE_REMOTE
  fi

  mkdir -p /backup

  while true; do
    upload_backup
    sync_storage
    cleanup_local
    cleanup_remote_db
    log "backup complete; next run in ${SYNC_INTERVAL_SECONDS}s"
    sleep "${SYNC_INTERVAL_SECONDS}"
  done
}

main "$@"
