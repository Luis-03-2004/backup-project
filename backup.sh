#!/bin/bash

# Exit the script if any command fails
set -e

# 1. Load configuration from .env
source .env

# Create a timestamp and ensure the destination directory exists
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_NAME="db_dump_$TIMESTAMP.sql.gz"
DESTINATION_FILE="$BACKUP_DESTINATION_DIR/$BACKUP_NAME"

mkdir -p "$BACKUP_DESTINATION_DIR"

# 2. Extract the variables from the .env file of the target project (tr -d '\r' removes unwanted line breaks)
DB_CONNECTION=$(grep '^DB_CONNECTION=' "$TARGET_PROJECT_ENV_PATH" | cut -d '=' -f2 | tr -d '\r')
DB_HOST=$(grep '^DB_HOST=' "$TARGET_PROJECT_ENV_PATH" | cut -d '=' -f2 | tr -d '\r')
DB_DATABASE=$(grep '^DB_DATABASE=' "$TARGET_PROJECT_ENV_PATH" | cut -d '=' -f2 | tr -d '\r')
DB_USERNAME=$(grep '^DB_USERNAME=' "$TARGET_PROJECT_ENV_PATH" | cut -d '=' -f2 | tr -d '\r')
DB_PASSWORD=$(grep '^DB_PASSWORD=' "$TARGET_PROJECT_ENV_PATH" | cut -d '=' -f2 | tr -d '\r')

echo "Starting database dump: $DB_DATABASE ($DB_CONNECTION)..."

# 3. Do the dump and compress on-the-fly
if [ "$DB_CONNECTION" == "mysql" ]; then
    mysqldump -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" | gzip > "$DESTINATION_FILE"
else
    echo "Error: Database '$DB_CONNECTION' not supported."
    exit 1
fi

echo "Dump completed successfully! Saved at: $DESTINATION_FILE"

# 4. Retention routine (Keep only the last X backups)
echo "Cleaning old backups (keeping the last $MAX_BACKUPS_TO_KEEP)..."
cd "$BACKUP_DESTINATION_DIR" || exit

# List the files sorted by date (oldest first), ignore the X most recent, and delete the rest
ls -1tr | head -n -"$MAX_BACKUPS_TO_KEEP" | xargs -r rm -f --

echo "Process finished!"