# Generic Remote Database Backup Tool

A lightweight Bash script designed to connect to a remote database server via an open port, perform a database dump, and manage local backups with a retention policy.

## Features
- **Remote Connection:** Connects directly to any database host (e.g., AWS, local network servers) using Host, Port, and Credentials.
- **Smart Cross-Compatibility:** Automatically detects the environment to apply necessary flags like `--column-statistics=0` and `--hex-blob` , ensuring seamless backups between MySQL 8.0+ and MariaDB.
- **Unified backup archives:** Each run produces one `backup_<timestamp>.tar.gz` in your backup directory. Inside: the database dump as a `.sql` file and, when storage sync is enabled, the remote storage tree under `storage/`. DB and storage for that run stay paired, and retention applies to these archives only.
- **Retention Policy:** Automatically deletes older `backup_*.tar.gz` files, keeping only the most recent ones (configurable).

## Prerequisites
- `bash`
- `mysqldump`
- `tar` and `gzip` (for `tar.gz` archives)

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
   | --ssh-password | SSH password used with `sshpass` authentication |
   | --no-password | Use SSH agent/authorized_keys (no password prompt) |
   | --user | Remote SSH user (e.g. `admin`, `ubuntu`) |
   | --no-storage | Skip the storage sync and perform only the DB dump |

> **Note:** For password authentication, the `sshpass` utility must be installed on your system (`sudo apt install sshpass` on Debian/Ubuntu).

> **Storage backup and PEM keys:** When syncing storage over SSH with a `.pem` private key, run the script with `sudo` (e.g. `sudo ./backup.sh`) so the key can stay locked down with strict permissions (`chmod 600` or similar). Avoid loosening key permissions with `chmod` just to make `scp` work as a normal user—that exposes the private key on disk. Use an absolute path for `PEM_KEY` in `.env` when using `sudo`, since the working environment may differ.

**Examples:**

- Full backup (DB + Storage) using a specific key:
   ```bash
   sudo ./backup.sh --db-host 00.000.000.00 --key /home/you/.ssh/my-key.pem --remote-storage "/var/www/app/storage"
   ```
- Database-only backup (skipping storage):
   ```bash
   ./backup.sh --db-host 00.000.000.00 --db-port 3306 --db-database app_db --db-username app_user --db-password "secret" --backup-dir "/tmp/backups" --retention 3 --user ubuntu --no-storage
   ```
- Quick test for a different DB user:
   ```bash
   ./backup.sh --db-host 1.2.3.4 --db-username temporary-admin
   ```
- Backup using password authentication
   ```bash
   ./backup.sh --db-host 1.2.3.4 --ssh-password "my-ssh-password"
   ```
   
## Usage
- Run the script manually (from the project directory, or after `cd` there—see script behavior):
  ```bash
  ./backup.sh
  ```
- For **storage sync with a PEM key**, prefer **`sudo ./backup.sh`** so private key permissions stay strict; see the note above.

## Restoration

This project focuses on backup generation, but restoring backups is also essential for disaster recovery and validation.

### Prerequisites
- `mysql` client installed on the machine where you run the restore command
- Network access to the database you are restoring **into** (local `127.0.0.1` or any remote host)
- A backup archive from this project: `backup_<timestamp>.tar.gz`

### Important
Restoration can overwrite existing data.  
Before restoring in production, create a safety backup of the current database.  
Create the target database first if it does not exist (`CREATE DATABASE your_database;`).

---

### What is inside `backup_<timestamp>.tar.gz`?

Each archive contains:

- **`dump_<database>_<timestamp>.sql`** — plain SQL from `mysqldump` (this is what you pipe into `mysql`)
- **`storage/`** (optional) — copy of the remote storage folder from that same backup run

---

### Step 1 — See what is in the archive (optional)

```bash
tar -tzf /path/to/your/backups/backup_2026-04-01_12-00-00.tar.gz
```

Note the exact `.sql` filename (it includes your database name and the backup timestamp).

---

### Step 2 — Extract the archive

Pick any empty or temporary folder:

```bash
mkdir -p /tmp/restore
tar -xzf /path/to/your/backups/backup_2026-04-01_12-00-00.tar.gz -C /tmp/restore
ls -la /tmp/restore
```

You should see the `dump_*.sql` file (and `storage/` if that backup included storage).

---

### Step 3 — Restore the dump into a database

The pattern is always: **`mysql` connects to a host, then reads the `.sql` file on stdin.**

**Local database** (MySQL/MariaDB on this machine):

```bash
mysql -h 127.0.0.1 -P 3306 -u your_user -p your_database < /tmp/restore/dump_your_db_2026-04-01_12-00-00.sql
```

**Remote database** (another server — change host, port, user, and database name):

```bash
mysql -h db.example.com -P 3306 -u your_user -p your_database < /tmp/restore/dump_your_db_2026-04-01_12-00-00.sql
```

`-p` alone will prompt for a password; you can use `-p'your_password'` instead (less safe on shared machines).

---

### Optional — Pipe the dump straight from the tarball (no folder left on disk)

If there is only one `.sql` file in the archive:

```bash
SQL_PATH=$(tar -tzf /path/to/backup_2026-04-01_12-00-00.tar.gz | grep '\.sql$' | head -1)
tar -xOf /path/to/backup_2026-04-01_12-00-00.tar.gz "$SQL_PATH" | mysql -h 127.0.0.1 -P 3306 -u your_user -p your_database
```

---

### Restore storage

Copy the extracted `storage/` tree back to your application server at the path your app expects (layout mirrors `REMOTE_STORAGE_PATH` from the remote host at backup time).

---

### Verify the database restore

```bash
mysql -h 127.0.0.1 -P 3306 -u your_user -p -e "USE your_database; SHOW TABLES;"
```

### Common issues
- `Access denied`: verify user, password, and host permissions (`GRANT` on the server).
- `Unknown database`: create the database first or fix the name in the `mysql` command.
- `Charset/collation errors`: validate compatibility between source and target MySQL/MariaDB versions.
