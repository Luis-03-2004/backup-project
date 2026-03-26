# Generic Remote Database Backup Tool

A lightweight Bash script designed to connect to a remote database server via an open port, perform a database dump, and manage local backups with a retention policy.

## Features
- **Remote Connection:** Connects directly to any database host (e.g., AWS, local network servers) using Host, Port, and Credentials.
- **Smart Cross-Compatibility:** Automatically detects the environment to apply necessary flags like `--column-statistics=0` and `--hex-blob` , ensuring seamless backups between MySQL 8.0+ and MariaDB.
- **Automated Compression:** Dumps are compressed on-the-fly using `gzip` (`.sql.gz`).
- **Retention Policy:** Automatically deletes old backups, keeping only the most recent ones (configurable).

## Prerequisites
- `bash`
- `mysqldump`
- `gzip`

## Setup & Configuration

### 1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
   
### 2. Edit your `.env` file with your local paths:
   ```
   # Remote Database Configuration
   DB_HOST="000.000.00.000"
   DB_PORT="3306"
   DB_DATABASE="your-remote-db"
   DB_USERNAME="db-user"
   DB_PASSWORD="your-strong-password"

   # Remote SSH Configuration (for storage sync)
   REMOTE_USER="ubuntu"
   REMOTE_STORAGE_PATH="/var/www/app/storage"
   PEM_KEY="/path/to/your/pem/key"

   # Local Destination & Retention
   BACKUP_DESTINATION_DIR="/path/to/your/local/dumps"
   MAX_BACKUPS_TO_KEEP=5

   SKIP_STORAGE=false

   ```
### 3. Manual execution with Arguments

   You can override any setting without touching the .env file. This is useful for one-time backups or connecting to different envinroments.

   | Argument | Description |
   | :--- | :--- |
   | --db-host | Remote database host (IP or DNS) |
   | --db-port | Remote database port |
   | --db-database | Database name to dump |
   | --db-username | Database username |
   | --db-password | Database password |
   | --backup-dir | Local backup destination directory |
   | --retention | Number of backups to keep |
   | --remote-storage | Absolute path to the remote storage folder |
   | --key | Path to your `.pem` private key |
   | --user | Remote SSH user (e.g. `admin`, `ubuntu`) |
   | --no-storage | Skip the storage sync and perform only the DB dump |

**Examples:**

- Full backup (DB + Storage) using a specific key:
   ```bash
   ./backup.sh --db-host 00.000.000.00 --key ~/.ssh/my-key.pem --remote-storage "/var/www/app/storage"
   ```
- Database-only backup (skipping storage):
   ```bash
   ./backup.sh --db-host 00.000.000.00 --db-port 3306 --db-database app_db --db-username app_user --db-password "secret" --backup-dir "/tmp/backups" --retention 3 --user ubuntu --no-storage
   ```
- Quick test for a different DB user:
   ```bash
   ./backup.sh --db-host 1.2.3.4 --db-username temporary-admin
   ```
   
## Usage
- Run the script manually:
  ```bash
  ./backup.sh
  ``` 
## Restoration
To restore a compressed database backup, you can use the following command:
```bash
zcat path/to/backup/dump_file.sql.gz | mysql -h localhost -u your_user -p your_database
```