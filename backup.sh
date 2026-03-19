#!/bin/bash

# Exit the script if any command fails
set -e

# 1. Load configuration from .env
source .env

# 2. Prepare the destination and backup file name
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="remote_dump_${DB_DATABASE}_${TIMESTAMP}.sql.gz"
DESTINATION_FILE="$BACKUP_DESTINATION_DIR/$BACKUP_NAME"

mkdir -p "$BACKUP_DESTINATION_DIR"

echo "Starting remote connection to backup database: $DB_DATABASE at $DB_HOST:$DB_PORT..."

# 3. Run a remote mysqldump and compress on-the-fly (with MariaDB/MySQL8 compatibility flag)
mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" --column-statistics=0 "$DB_DATABASE" 2>/dev/null | gzip > "$DESTINATION_FILE"

echo "Dump completed successfully! Saved at: $DESTINATION_FILE"

# 4. Retention routine (Keep only the last X backups)
echo "Cleaning old backups (keeping the last $MAX_BACKUPS_TO_KEEP)..."
cd "$BACKUP_DESTINATION_DIR" || exit
ls -1tr | head -n -"$MAX_BACKUPS_TO_KEEP" | xargs -r rm -f --

echo "Process finished!"