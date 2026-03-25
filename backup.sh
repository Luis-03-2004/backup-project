#!/bin/bash

# Exit the script if any command fails
set -e

# 1. Load configuration from .env
if [ -f .env ]; then
    # Use a more stable way to export .env variables
    set -a
    source .env
    set +a
fi

# 2. Parse Command Line Arguments
# We initialize variables with values from .env (if they exist)
# This way, the argument parser only overwrites if a flag is passed.
while [[ $# -gt 0 ]]; do
    case $1 in
        --host) DB_HOST="$2"; shift 2 ;;
        --user) REMOTE_USER="$2"; shift 2 ;;
        --key)  PEM_KEY="$2"; shift 2 ;;
        --storage-path) REMOTE_STORAGE_PATH="$2"; shift 2 ;;
        --no-storage) SKIP_STORAGE=true; shift ;;
        *) shift ;;
    esac
done

# 3. Validation & Setup
# We use the variable if it exists, otherwise we fail.
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FINAL_BACKUP_DIR="${BACKUP_DESTINATION_DIR}"
FINAL_MAX_RETAIN="${MAX_BACKUPS_TO_KEEP}"
FINAL_STORAGE_PATH="${REMOTE_STORAGE_PATH}"

if [ -z "$FINAL_BACKUP_DIR" ] || [ -z "$FINAL_MAX_RETAIN" ]; then
    echo "Error: BACKUP_DESTINATION_DIR or MAX_BACKUPS_TO_KEEP is missing."
    exit 1
fi

mkdir -p "$FINAL_BACKUP_DIR/db"
mkdir -p "$FINAL_BACKUP_DIR/storage"

# 4. SSH Logic
SSH_OPTS=""
if [ -n "$PEM_KEY" ] && [ -f "$PEM_KEY" ]; then
    SSH_OPTS="-i $PEM_KEY"
    echo "Using PEM Key: $PEM_KEY"
fi

# 5. Database Backup
echo "Starting Remote MySQL Dump..."
DB_FILE="$FINAL_BACKUP_DIR/db/dump_${DB_DATABASE}_${TIMESTAMP}.sql.gz"

mysqldump -h "$DB_HOST" -P "${DB_PORT}" -u "$DB_USERNAME" -p"$DB_PASSWORD" \
    --column-statistics=0 --skip-lock-tables "$DB_DATABASE" | gzip > "$DB_FILE"

if [ ! -s "$DB_FILE" ]; then
    echo "Error: DB backup failed."
    exit 1
fi
echo "DB Backup saved: $DB_FILE"

# 6. Storage Backup
if [ "$SKIP_STORAGE" != true ]; then
    if [ -z "$FINAL_STORAGE_PATH" ]; then
        echo "Error: REMOTE_STORAGE_PATH is not defined."
        exit 1
    fi

    echo "Syncing Storage from: $FINAL_STORAGE_PATH"
    LOCAL_TMP="$FINAL_BACKUP_DIR/storage/storage_${TIMESTAMP}"
    
    # The actual SCP command
    scp -r $SSH_OPTS "$REMOTE_USER@$DB_HOST:$FINAL_STORAGE_PATH" "$LOCAL_TMP"
    
    tar -czf "${LOCAL_TMP}.tar.gz" -C "$FINAL_BACKUP_DIR/storage" "storage_${TIMESTAMP}"
    rm -rf "$LOCAL_TMP"
    echo "Storage Backup saved: ${LOCAL_TMP}.tar.gz"
fi

# 7. Retention
echo "Cleaning old backups (Keeping: $FINAL_MAX_RETAIN)..."
ls -dt "$FINAL_BACKUP_DIR/db/"* 2>/dev/null | tail -n +$((FINAL_MAX_RETAIN + 1)) | xargs -r rm -rf || true
ls -dt "$FINAL_BACKUP_DIR/storage/"* 2>/dev/null | tail -n +$((FINAL_MAX_RETAIN + 1)) | xargs -r rm -rf || true

echo "Process finished successfully!"