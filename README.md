# Generic Remote Database Backup Tool

A lightweight Bash script designed to connect to a remote database server via an open port, perform a database dump, and manage local backups with a retention policy.

## Features
- **Remote Connection:** Connects directly to any database host (e.g., AWS, local network servers) using Host, Port, and Credentials.
- **Cross-Compatibility:** Includes flags (`--column-statistics=0`) to ensure compatibility when dumping from MariaDB servers using MySQL 8 clients.
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

   # Local Destination & Retention
   BACKUP_DESTINATION_DIR="/path/to/your/local/dumps"
   MAX_BACKUPS_TO_KEEP=5

   ```
### 3. Manual execution with Arguments

   You can override any setting without touching the .env file. This is useful for one-time backups or connecting to different envinroments.

   | Argument | Description |
   | :--- | :---: |
   | --host | Remote database IP or DNS |
   | --user| Remote SSH user (e.g. , admin, ubuntu) |
   | --key | Path to your .pem private key |
   | --storage-path | Absolute path to the remote storage folder |
   | --no-storage | Skip the storage sync and perform only the DB dump |

**Examples:**

- Full backup (DB + Storage) using a specific key:
   ```bash
   ./backup.sh --host 00.000.000.00 --key ~/.ssh/my-key.pem --storage-path "/var/www/app/storage"
   ```
- Database-only backup (skipping storage):
   ```bash
   ./backup.sh --no-storage
   ```
- Quick test for a different DB user:
   ```bash
   ./backup.sh --user temporary-admin --host 1.2.3.4
   ```

### 4. Make the script executtable:
   ```bash
   chmod +x backup.sh
   ```
   
## Usage
- Run the script manually:
  ```bash
  ./backup.sh
  ``` 
