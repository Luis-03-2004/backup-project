#!/bin/bash

# Exit the script if any command fails
set -e

# Validate required variables
validate_required() {
    local var_value=$1
    local var_name=$2
    local var_flag=$3
    local hint=${4:-}
    if [ -z "$var_value" ]; then
        echo "Error: Required variable '$var_name' is missing. edit '.env' setting '$var_name' or use inline command with '$var_flag'."
        [ -n "$hint" ] && echo "$hint"
        exit 1
    fi
}

run_storage_scp() {
    local dest_dir=$1
    if [ -n "$PEM_KEY" ] && [ -f "$PEM_KEY" ]; then
        echo "Using PEM Key for authentication."
        scp -r $SSH_OPTS -i "$PEM_KEY" \
            "$REMOTE_USER@$DB_HOST:$REMOTE_STORAGE_PATH" "$dest_dir"
    elif [ "$NO_PASSWORD" = true ]; then
        echo "Attempting connection without password (NO_PASSWORD mode)."
        scp -r $SSH_OPTS \
            "$REMOTE_USER@$DB_HOST:$REMOTE_STORAGE_PATH" "$dest_dir"
    elif [ -n "$SSH_PASSWORD" ]; then
        if command -v sshpass >/dev/null 2>&1; then
            echo "Using password authentication via sshpass."
            SSHPASS="$SSH_PASSWORD" sshpass -e scp -r $SSH_OPTS \
                "$REMOTE_USER@$DB_HOST:$REMOTE_STORAGE_PATH" "$dest_dir"
        else
            echo "Error: 'sshpass' is not installed, but password auth was requested."
            echo "Provide one of the options below:"
            echo "  - ENV: SSH_PASSWORD=your-password | PARAM: --ssh-password your-password"
            echo "  - ENV: PEM_KEY=/path/to/key.pem   | PARAM: --key /path/to/key.pem"
            echo "  - ENV: NO_PASSWORD=true           | PARAM: --no-password"
            rm -rf "$WORK"
            exit 1
        fi
    else
        echo "Error: No authentication method found for storage sync."
        echo "Provide one of the options below:"
        echo "  1) PEM key:"
        echo "     ENV: PEM_KEY=/path/to/key.pem"
        echo "     PARAM: --key /path/to/key.pem"
        echo "  2) SSH password (requires sshpass):"
        echo "     ENV: SSH_PASSWORD=your-password"
        echo "     PARAM: --ssh-password your-password"
        echo "  3) Passwordless SSH (ssh-agent/authorized_keys):"
        echo "     ENV: NO_PASSWORD=true"
        echo "     PARAM: --no-password"
        rm -rf "$WORK"
        exit 1
    fi
}
# 1. Load configuration from .env
cd "$(dirname "$0")"

if [ -f .env ]; then
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
        *) shift ;;
    esac
done

# 3. Validation & Setup
# We use the variable if it exists, otherwise we fail.
validate_required "$DB_HOST" "DB_HOST" "--db-host"
validate_required "$DB_PORT" "DB_PORT" "--db-port"
validate_required "$DB_DATABASE" "DB_DATABASE" "--db-database"
validate_required "$DB_USERNAME" "DB_USERNAME" "--db-username"
validate_required "$DB_PASSWORD" "DB_PASSWORD" "--db-password"
validate_required "$BACKUP_DESTINATION_DIR" "BACKUP_DESTINATION_DIR" "--backup-dir"
validate_required "$MAX_BACKUPS_TO_KEEP" "MAX_BACKUPS_TO_KEEP" "--retention"

STORAGE_OPTIONAL_HINT="Note: Remote folder backup is optional; disable it with the --no-storage flag."

if [ "$SKIP_STORAGE" != true ]; then
    validate_required "$REMOTE_STORAGE_PATH" "REMOTE_STORAGE_PATH" "--remote-storage" "$STORAGE_OPTIONAL_HINT"
    validate_required "$REMOTE_USER" "REMOTE_USER" "--user" "$STORAGE_OPTIONAL_HINT"
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

mkdir -p "$BACKUP_DESTINATION_DIR"

# Remove incomplete staging dirs from interrupted runs
for entry in "$BACKUP_DESTINATION_DIR"/.work_*; do
    [ -d "$entry" ] && rm -rf "$entry"
done 2>/dev/null || true

# 4. MySQL / MariaDB client compatibility (options vary by version)
COLUMN_STATS=""
if mysqldump --help 2>/dev/null | grep -q "column-statistics"; then
    COLUMN_STATS="--column-statistics=0"
fi

# Prefer legacy --skip-ssl; newer MySQL clients use --ssl-mode=DISABLED instead
DUMP_SSL_SKIP=""
if mysqldump --help 2>/dev/null | grep -q -- '--skip-ssl'; then
    DUMP_SSL_SKIP="--skip-ssl"
elif mysqldump --help 2>/dev/null | grep -q -- '--ssl-mode'; then
    DUMP_SSL_SKIP="--ssl-mode=DISABLED"
fi

WORK="$BACKUP_DESTINATION_DIR/.work_${TIMESTAMP}"
mkdir -p "$WORK"

# 5. Storage sync (uncompressed tree under WORK/storage/)
SSH_OPTS="-o BatchMode=no -o ConnectTimeout=10 -o StrictHostKeyChecking=no"


if [ "$SKIP_STORAGE" != true ]; then
    echo "Preparing storage sync..."
    mkdir -p "$WORK/storage"
    echo "Syncing Storage from: $REMOTE_STORAGE_PATH"
    run_storage_scp "$WORK/storage/"
    if [ -z "$(ls -A "$WORK/storage" 2>/dev/null)" ]; then
        rm -rf "$WORK"
        echo "Error: storage sync failed or remote folder is empty."
        exit 1
    fi
fi

# 6. Database dump (plain .sql inside WORK; archived together with storage in one .tar.gz)
echo "Starting Remote MySQL Dump..."
DB_FILE="$WORK/dump_${DB_DATABASE}_${TIMESTAMP}.sql"

mysqldump -h "$DB_HOST" -P "${DB_PORT}" -u "$DB_USERNAME" -p"$DB_PASSWORD" \
    $COLUMN_STATS $DUMP_SSL_SKIP --skip-lock-tables --hex-blob "$DB_DATABASE" > "$DB_FILE" || {
    rm -rf "$WORK"
    exit 1
}

if [ ! -s "$DB_FILE" ]; then
    rm -rf "$WORK"
    echo "Error: DB backup failed."
    exit 1
fi

BACKUP_ARCHIVE="$BACKUP_DESTINATION_DIR/backup_${TIMESTAMP}.tar.gz"
echo "Creating unified backup archive..."
tar -czf "$BACKUP_ARCHIVE" -C "$WORK" .
rm -rf "$WORK"

echo "Backup saved: $BACKUP_ARCHIVE"

# 7. Retention (one counter per unified backup file)
echo "Cleaning old backups (Keeping: $MAX_BACKUPS_TO_KEEP)..."
ls -dt "$BACKUP_DESTINATION_DIR"/backup_*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS_TO_KEEP + 1)) | xargs -r rm -f || true

echo "Process finished successfully!"
