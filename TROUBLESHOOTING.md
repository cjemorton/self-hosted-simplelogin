# SimpleLogin Troubleshooting Guide

This guide helps you diagnose and resolve common issues when self-hosting SimpleLogin.

## Table of Contents

- [Quick Diagnostic Tools](#quick-diagnostic-tools)
- [Common Issues](#common-issues)
  - [Migration Failures](#migration-failures)
  - [Database Connection Issues](#database-connection-issues)
  - [Container Startup Issues](#container-startup-issues)
  - [Email Delivery Problems](#email-delivery-problems)
  - [SSL/TLS Certificate Issues](#ssltls-certificate-issues)
- [Diagnostic Scripts](#diagnostic-scripts)
- [Getting Help](#getting-help)

## Quick Diagnostic Tools

Before starting, run these diagnostic scripts to identify issues:

### Pre-flight Check

Run this **before** starting the stack to validate your configuration:

```bash
bash scripts/preflight-check.sh
```

This checks:
- ✓ Required environment variables
- ✓ Docker installation and configuration
- ✓ Required files (DKIM keys, compose files)
- ✓ Disk space availability
- ✓ Port availability

### Full Diagnostics

If you're experiencing issues, collect comprehensive diagnostic information:

```bash
bash scripts/diagnose.sh
```

This creates a timestamped log file with:
- System information
- Docker and container status
- Container logs
- Configuration (with sensitive data hidden)
- Network and volume information

## Common Issues

### Migration Failures

**Symptom:** `sl-migration` container exits with code 1 or code 2

#### Cause 1: Database Not Ready

The migration service starts before PostgreSQL is fully initialized.

**Solution:**
- The `run-migration.sh` script includes robust database waiting logic with automatic fallback
- By default, it waits 60 seconds for the database to be ready
- If your database takes longer to initialize, increase the timeout:
  ```bash
  # Add to .env file
  DB_WAIT_TIMEOUT=120  # Wait up to 120 seconds
  ```
- Check postgres logs: `docker logs sl-db`
- Verify healthcheck is passing: `docker ps` (should show "healthy" status)

**Technical Note:**
The SimpleLogin Docker image does not include PostgreSQL client tools (`pg_isready`, `psql`). The wait-for-db.sh script automatically detects this and uses Python/psycopg2 (which is available in the image) to perform database connectivity checks. This ensures reliable database readiness detection regardless of which tools are available.

**Manual verification:**
```bash
# Check if database is ready from migration container
docker compose exec migration python3 -c "import psycopg2; conn = psycopg2.connect('$DB_URI'); conn.close(); print('DB ready')"

# Check database logs
docker logs sl-db --tail 50
```

#### Cause 2: Incorrect Database Credentials

**Symptoms:**
- "password authentication failed"
- "role does not exist"

**Solution:**
1. Verify credentials in `.env`:
   ```bash
   cat .env | grep POSTGRES
   ```

2. If this is a fresh install and credentials are wrong:
   ```bash
   # Stop and remove everything
   docker compose down -v
   
   # Remove database volume
   sudo rm -rf db/
   
   # Fix credentials in .env, then restart
   docker compose up -d
   ```

3. If you're upgrading and database already exists with different credentials:
   - Update `.env` to match the existing database credentials
   - OR update database credentials to match `.env`

#### Cause 3: Database Schema Issues

**Symptom:** "relation does not exist" or "version conflicts"

**Solution:**
```bash
# Check current Alembic revision
docker compose run --rm migration alembic current

# Check target revision
docker compose run --rm migration alembic heads

# View migration history
docker compose run --rm migration alembic history
```

For version conflicts, see the [How-to Upgrade](README.md#how-to-upgrade-from-340) section.

### Database Connection Issues

**Symptom:** Services cannot connect to database

**Quick checks:**
```bash
# 1. Is database container running?
docker ps | grep sl-db

# 2. Is database healthy?
docker inspect sl-db | grep -A 10 Health

# 3. Can other containers reach the database?
docker compose exec app ping -c 3 sl-db

# 4. Check database port
docker port sl-db
```

**Solution:**
```bash
# Restart database
docker compose restart postgres

# Check database logs for errors
docker logs sl-db --tail 100

# Verify DB_URI in .env
cat .env | grep DB_URI
```

### Container Startup Issues

**Symptom:** Containers fail to start or keep restarting

#### Check Container Status
```bash
# View all containers and their status
docker ps -a

# Check specific container logs
docker logs sl-app --tail 100
docker logs sl-migration --tail 100
```

#### Common Startup Issues

**Port conflicts:**
```bash
# Check which ports are in use
sudo netstat -tuln | grep -E ':(25|80|443|587|5432|7777)'

# Or with ss
sudo ss -tuln | grep -E ':(25|80|443|587|5432|7777)'
```

**Volume permission issues:**
```bash
# Check permissions
ls -la db/ pgp/ upload/

# Fix if needed (be careful!)
sudo chown -R $(id -u):$(id -g) db/ pgp/ upload/
```

**Out of disk space:**
```bash
# Check disk usage
df -h

# Clean up Docker resources
docker system prune -a
```

### Email Delivery Problems

**Symptom:** Emails not being sent or received

#### Check Email Handler
```bash
# Is email handler running?
docker ps | grep sl-email

# Check email handler logs
docker logs sl-email --tail 100
```

#### Check Postfix
```bash
# Is Postfix running?
docker ps | grep postfix

# Check Postfix logs
docker logs postfix --tail 100

# Check mail queue
docker compose exec postfix mailq
```

#### DNS Configuration
Verify your DNS records are correctly configured:

```bash
# Check MX record
dig @1.1.1.1 $DOMAIN mx

# Check SPF record
dig @1.1.1.1 $DOMAIN txt

# Check DKIM record
dig @1.1.1.1 dkim._domainkey.$DOMAIN txt

# Check DMARC record
dig @1.1.1.1 _dmarc.$DOMAIN txt
```

### SSL/TLS Certificate Issues

**Symptom:** Certificate errors or HTTPS not working

#### Check Traefik
```bash
# Is Traefik running?
docker ps | grep traefik

# Check Traefik logs
docker logs traefik --tail 100

# Check certificate storage
docker volume inspect traefik-acme
```

#### Check Certificate Exporter
```bash
# Is cert exporter running?
docker ps | grep cert-exporter

# Check logs
docker logs cert-exporter --tail 100

# List extracted certificates
docker compose exec postfix ls -la /certs/
```

#### Let's Encrypt Rate Limits
If you're hitting rate limits:

1. Use staging server for testing:
   ```yaml
   # In traefik-compose.yaml, uncomment:
   - --certificatesresolvers.tls.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
   ```

2. Wait for rate limit to reset (see https://letsencrypt.org/docs/rate-limits/)

## Diagnostic Scripts

### wait-for-db.sh

Waits for PostgreSQL to be ready before proceeding.

**Usage:**
```bash
# Wait up to 60 seconds (default)
bash scripts/wait-for-db.sh

# Wait up to 120 seconds
bash scripts/wait-for-db.sh 120
```

**Environment variables required:**
- `POSTGRES_HOST` or parsed from `DB_URI`
- `POSTGRES_PORT` or parsed from `DB_URI`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`

### run-migration.sh

Runs database migrations with comprehensive error handling.

**Usage:**
```bash
# Run migrations (typically called by docker compose)
bash scripts/run-migration.sh
```

**Environment variables:**
- `DB_WAIT_TIMEOUT` - Timeout in seconds for database to be ready (default: 60)

**Features:**
- Waits for database to be ready
- Runs Alembic migrations
- Provides detailed error messages
- Suggests troubleshooting steps

**Increasing Database Wait Timeout:**

If your database takes longer to initialize, you can increase the wait timeout:

```bash
# Add to .env file
DB_WAIT_TIMEOUT=120  # Wait up to 120 seconds
```

This is particularly useful for:
- Slow hardware or resource-constrained systems
- First-time database initialization
- Large databases with long recovery times

### preflight-check.sh

Validates configuration before starting the stack.

**Usage:**
```bash
# Check default .env file
bash scripts/preflight-check.sh

# Check specific env file
bash scripts/preflight-check.sh /path/to/.env
```

**Checks:**
- Environment file exists
- Required variables are set
- Docker and Docker Compose installed
- Required files present
- Sufficient disk space
- Port availability

### diagnose.sh

Collects comprehensive diagnostic information.

**Usage:**
```bash
# Save to default file (timestamped)
bash scripts/diagnose.sh

# Save to specific file
bash scripts/diagnose.sh my-diagnostics.log
```

**Collects:**
- System information (hostname, uptime, disk, memory)
- Docker version and configuration
- Container status and logs
- Docker Compose configuration
- Environment configuration (sanitized)
- Network and volume information
- Database connectivity test

## Getting Help

### Before Asking for Help

1. Run the diagnostic script:
   ```bash
   bash scripts/diagnose.sh
   ```

2. Review the output for obvious errors

3. Check container logs:
   ```bash
   docker logs sl-migration
   docker logs sl-db
   docker logs sl-app
   ```

### Where to Get Help

1. **GitHub Issues**: https://github.com/simple-login/app/issues
   - Search existing issues first
   - Include your diagnostic log (remove sensitive data!)

2. **SimpleLogin Community**: Check the SimpleLogin website for community resources

### Information to Include

When asking for help, provide:

1. **Environment:**
   - OS and version
   - Docker version: `docker --version`
   - Docker Compose version: `docker compose version`
   - SimpleLogin version from `.env`

2. **What you were trying to do:**
   - Fresh install or upgrade?
   - What command did you run?

3. **What happened:**
   - Error messages (full text)
   - Container logs
   - Diagnostic output

4. **What you've tried:**
   - Steps you've already taken
   - Configuration changes

## Advanced Troubleshooting

### Accessing Container Shell

```bash
# Access running app container
docker compose exec app bash

# Access database
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

# Run one-off command
docker compose run --rm app python manage.py shell
```

### Viewing Real-time Logs

```bash
# Follow all logs
docker compose logs -f

# Follow specific service
docker compose logs -f app

# Multiple services
docker compose logs -f app email job-runner
```

### Resetting Everything (Nuclear Option)

**WARNING:** This deletes ALL data!

```bash
# Stop everything
docker compose down -v

# Remove data
sudo rm -rf db/ pgp/ upload/

# Remove Docker volumes
docker volume prune -f

# Start fresh
docker compose up -d
```

### Testing Email Delivery

```bash
# Send test email through Postfix
docker compose exec postfix sendmail -v your-email@example.com
Subject: Test
This is a test message.
.
(Press Ctrl+D)
```

### Checking Migration State

```bash
# Show current database revision
docker compose run --rm migration alembic current

# Show available revisions
docker compose run --rm migration alembic heads

# Show migration history
docker compose run --rm migration alembic history --verbose
```

## Preventive Measures

### Regular Maintenance

1. **Monitor disk space:**
   ```bash
   df -h
   ```

2. **Clean up Docker resources:**
   ```bash
   docker system prune -a --volumes
   ```

3. **Backup database regularly:**
   ```bash
   docker compose exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > backup.sql
   ```

4. **Keep Docker images updated:**
   ```bash
   docker compose pull
   docker compose up -d
   ```

### Before Upgrading

1. **Backup everything:**
   ```bash
   # Database
   docker compose exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB -F c > backup.dump
   
   # Files
   tar -czf simplelogin-backup.tar.gz db/ pgp/ upload/ dkim.key dkim.pub.key .env
   ```

2. **Read upgrade notes:**
   - Check [README.md](README.md) for upgrade instructions
   - Review SimpleLogin's changelog
   - Check for breaking changes

3. **Test in staging first** (if possible)

### Monitoring

Set up monitoring for:
- Disk space (should have >10GB free)
- Container status (all should be "Up" or "healthy")
- Certificate expiry (Let's Encrypt renews automatically)
- Email delivery (send test emails periodically)

---

**Last Updated:** 2026-02-01
