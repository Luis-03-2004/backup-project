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

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
   
2. Edit your `.env` file with your local paths:
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

3. Make the script executtable:
   ```bash
   chmod +x backup.sh
   ```
   
## Usage
- Run the script manually:
  ```bash
  ./backup.sh
  ``` 
