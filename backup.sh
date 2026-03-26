#!/bin/bash

# Exit the script if any command fails
set -e

# Validate required variables
validate_required() {
    local var_value=$1
    local var_name=$2
    
    if [ -z "$var_value" ]; then
        echo "Error: Required variable '$var_name' is missing."
        exit 1
    fi
}

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
        --db-host) DB_HOST="$2"; shift 2 ;;
        --db-port) DB_PORT="$2"; shift 2 ;;
        --db-database) DB_DATABASE="$2"; shift 2 ;;
        --db-username) DB_USERNAME="$2"; shift 2 ;;
        --db-password) DB_PASSWORD="$2"; shift 2 ;;
        --backup-dir) BACKUP_DESTINATION_DIR="$2"; shift 2 ;;
        --retention) MAX_BACKUPS_TO_KEEP="$2"; shift 2 ;;
        --remote-storage) REMOTE_STORAGE_PATH="$2"; shift 2 ;;
        --key)  PEM_KEY="$2"; shift 2 ;;
        --user) REMOTE_USER="$2"; shift 2 ;;
        --no-storage) SKIP_STORAGE=true; shift ;;
        --ssh-password) SSH_PASSWORD="$2"; shift 2 ;;
        --no-password) NO_PASSWORD=true; shift ;;
        --skip-ssl) SKIP_SSL=true; shift ;;
        *) shift ;;
    esac
done

# 3. Validation & Setup
# We use the variable if it exists, otherwise we fail.
validate_required "$DB_HOST" "DB_HOST"
validate_required "$DB_PORT" "DB_PORT"
validate_required "$DB_DATABASE" "DB_DATABASE"
validate_required "$DB_USERNAME" "DB_USERNAME"
validate_required "$DB_PASSWORD" "DB_PASSWORD"
validate_required "$BACKUP_DESTINATION_DIR" "BACKUP_DESTINATION_DIR"
validate_required "$MAX_BACKUPS_TO_KEEP" "MAX_BACKUPS_TO_KEEP"
validate_required "$REMOTE_USER" "REMOTE_USER"

if [ "$SKIP_STORAGE" != true ]; then
    validate_required "$REMOTE_STORAGE_PATH" "REMOTE_STORAGE_PATH"
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

mkdir -p "$BACKUP_DESTINATION_DIR/db"
mkdir -p "$BACKUP_DESTINATION_DIR/storage"

# 4. MySQL Compatibility Check (MySQL 8.0+ vs MariaDB)
COLUMN_STATS=""
if mysqldump --help | grep -q "column-statistics"; then
    COLUMN_STATS="--column-statistics=0"
fi

# 5. Database Backup

SSL_FLAG=""
[ "$SKIP_SSL" = true ] && SSL_FLAG="--skip-ssl"

echo "Starting Remote MySQL Dump..."
DB_FILE="$BACKUP_DESTINATION_DIR/db/dump_${DB_DATABASE}_${TIMESTAMP}.sql"

mysqldump -h "$DB_HOST" -P "${DB_PORT}" -u "$DB_USERNAME" -p"$DB_PASSWORD" \
    $COLUMN_STATS $SSL_FLAG --skip-lock-tables --hex-blob "$DB_DATABASE" > "$DB_FILE" || exit 1

if [ ! -s "$DB_FILE" ]; then
    echo "Error: DB backup failed."
    exit 1
fi

echo "Compressing dump file..."
gzip -f "$DB_FILE"

echo "DB Backup compressed and saved: ${DB_FILE}.gz"

# 6. SSH & Storage Logic
if [ "$SKIP_STORAGE" != true ]; then
    echo "Preparing storage sync..."
    
    SCP_CMD="scp -r"
    SSH_OPTS="-o BatchMode=no -o ConnectTimeout=10"

    if [ -n "$PEM_KEY" ] && [ -f "$PEM_KEY" ]; then
        # Option 1: PEM Key
        echo "Using PEM Key for authentication."
        SCP_CMD="$SCP_CMD -i $PEM_KEY $SSH_OPTS"
    elif [ "$NO_PASSWORD" = true ]; then
        # Option 2: No password (trust the SSH agent or authorized_keys)
        echo "Attempting connection without password (NO_PASSWORD mode)."
        SCP_CMD="$SCP_CMD $SSH_OPTS"
    elif [ -n "$SSH_PASSWORD" ]; then
        # Option 3: Password Using sshpass
        if command -v sshpass >/dev/null 2>&1; then
            echo "Using password authentication via sshpass."
            SCP_CMD="sshpass -p "$SSH_PASSWORD" $SCP_CMD $SSH_OPTS"
        else
            echo "Error: SSH_PASSWORD provided but 'sshpass' is not installed."
            exit 1
        fi
    else
        echo "Error: No authentication method found (Key, Password, or --no-password)."
        exit 1
    fi

    # Execution of the built command
    echo "Syncing Storage from: $REMOTE_STORAGE_PATH"
    LOCAL_TMP="$BACKUP_DESTINATION_DIR/storage/storage_${TIMESTAMP}"
    
    $SCP_CMD "$REMOTE_USER@$DB_HOST:$REMOTE_STORAGE_PATH" "$LOCAL_TMP"
    
    tar -czf "${LOCAL_TMP}.tar.gz" -C "$BACKUP_DESTINATION_DIR/storage" "storage_${TIMESTAMP}"
    rm -rf "$LOCAL_TMP"
    echo "Storage Backup saved: ${LOCAL_TMP}.tar.gz"
fi

# 7. Retention
echo "Cleaning old backups (Keeping: $MAX_BACKUPS_TO_KEEP)..."
ls -dt "$BACKUP_DESTINATION_DIR/db/"* 2>/dev/null | tail -n +$((MAX_BACKUPS_TO_KEEP + 1)) | xargs -r rm -rf || true
ls -dt "$BACKUP_DESTINATION_DIR/storage/"* 2>/dev/null | tail -n +$((MAX_BACKUPS_TO_KEEP + 1)) | xargs -r rm -rf || true

echo "Process finished successfully!"