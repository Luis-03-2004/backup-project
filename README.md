# Generic Local Database Backup Tool

A lightweight Bash script designed to automatically read database credentials from a target project's `.env` file (e.g., a Laravel project), perform a database dump, and manage local backups with a retention policy.

## Features
- **Auto-Discovery:** Extracts `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE`, `DB_HOST`, and `DB_CONNECTION` directly from the target project's `.env` file.
- **Cross-Database:** Supports  `mysql` database.
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
   # The absolute path to the .env file of your target project
   TARGET_PROJECT_ENV_PATH="/path/to/your/project/.env"

   # The local directory where you want to store the database dumps
   BACKUP_DESTINATION_DIR="/path/to/your/backups"

   # How many recent backups you want to keep
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
