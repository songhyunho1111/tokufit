#!/bin/sh
set -eu
umask 077
cd "$(dirname "$0")"
: "${BACKUP_REMOTE:?Set an SSH destination such as backups@backup-host:/srv/repick}"
mkdir -p backups
stamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="backups/repick-$stamp.dump"
trap 'rm -f "$archive.tmp"' EXIT HUP INT TERM
docker compose --env-file .env -f compose.yml exec -T postgres pg_dump -U postgres -d repick -Fc > "$archive.tmp"
test -s "$archive.tmp"
mv "$archive.tmp" "$archive"
scp "$archive" "$BACKUP_REMOTE/"
# Only expire local dumps after the off-host copy succeeds.
find backups -type f -name 'repick-*.dump' -mtime +14 -delete
