# Running SimpleLogin on Low-Resource VPS

This guide explains how to run SimpleLogin on resource-constrained systems, including 1 vCPU, 512MB-768MB RAM instances.

## Table of Contents

- [Overview](#overview)
- [Dynamic Resource Optimization](#dynamic-resource-optimization)
- [Minimum Requirements](#minimum-requirements)
- [Configuration](#configuration)
- [Monitoring and Tuning](#monitoring-and-tuning)
- [Troubleshooting](#troubleshooting)

## Overview

SimpleLogin includes **automatic resource optimization** that detects your system's available RAM and CPU, then dynamically configures all components for optimal performance. The system will:

- ✅ **Never crash** due to resource constraints
- ✅ **Automatically scale down** when RAM is low
- ✅ **Gracefully degrade** rather than fail
- ✅ **Show resource dashboard** at startup
- ✅ **Support manual overrides** for fine-tuning

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                   Container Startup                          │
│                                                              │
│  1. Detect System Resources (RAM, CPU)                      │
│  2. Calculate Optimal Configuration                          │
│  3. Apply Dynamic Settings                                   │
│  4. Display Resource Dashboard                               │
│  5. Start Service with Optimized Parameters                  │
└─────────────────────────────────────────────────────────────┘
```

## Dynamic Resource Optimization

### Resource Detection

At startup, SimpleLogin automatically detects:

- **Total RAM** (system memory)
- **Available RAM** (free memory)
- **CPU Cores** (processing capacity)

### Automatic Configuration

Based on detected resources, the system automatically tunes:

| Component | What Gets Tuned | Impact |
|-----------|----------------|---------|
| **Gunicorn (Web App)** | Worker count, timeout, max requests | Prevents timeouts and worker exhaustion |
| **Database** | Connection pool size | Reduces memory usage per connection |
| **Email Handler** | Thread count | Controls concurrent email processing |
| **Job Runner** | Thread count | Manages background task concurrency |

### Resource Tiers

The system operates in different modes based on available RAM:

| RAM Tier | RAM Range | Mode | Performance |
|----------|-----------|------|-------------|
| **CRITICAL** | < 256 MB | Emergency | System may not function |
| **LOW** | 256-768 MB | Degraded | Reduced workers, longer timeouts |
| **MEDIUM** | 768-2048 MB | Basic | Standard operation with some limits |
| **HIGH** | 2-4 GB | Good | Full features with good performance |
| **OPTIMAL** | > 4 GB | Maximum | All features at peak performance |

## Minimum Requirements

### Absolute Minimum (Not Recommended)
- **RAM:** 256 MB
- **CPU:** 1 vCPU
- **Disk:** 10 GB
- **Status:** Emergency mode, very slow

### Recommended Minimum
- **RAM:** 512-768 MB
- **CPU:** 1 vCPU
- **Disk:** 10 GB
- **Status:** Fully functional in degraded mode

### Comfortable Operation
- **RAM:** 1-2 GB
- **CPU:** 1-2 vCPU
- **Disk:** 20 GB
- **Status:** Good performance

### Optimal
- **RAM:** 4+ GB
- **CPU:** 2+ vCPU
- **Disk:** 50+ GB
- **Status:** Excellent performance

## Configuration

### Automatic Mode (Recommended)

No configuration needed! Simply start SimpleLogin:

```bash
./up.sh
```

The system will automatically detect resources and configure itself. You'll see a dashboard like this:

```
╔════════════════════════════════════════════════════════════════╗
║      SimpleLogin Dynamic Resource Optimization Dashboard       ║
╚════════════════════════════════════════════════════════════════╝

━━━ SYSTEM RESOURCES ━━━

  Total RAM:           768 MB  [LOW - DEGRADED MODE]
  Available RAM:       512 MB
  CPU Cores:             1

━━━ DYNAMIC CONFIGURATION ━━━

Web Application (Gunicorn):
  Workers:               2
  Timeout:              90 seconds
  Max Requests/Worker:  500

Database:
  Connection Pool Size:  5

Background Services:
  Email Handler Threads:  1
  Job Runner Threads:     1
```

### Forced Low-Memory Mode

For ultra-low-resource systems, force low-memory mode:

```bash
# Add to .env
LOW_MEMORY_MODE=true
```

This overrides detection and uses minimal resource settings regardless of actual available RAM.

### Manual Overrides

To manually control any setting, add to your `.env` file:

```bash
## Override automatic worker calculation
SL_GUNICORN_WORKERS_OVERRIDE=2

## Override timeout (seconds)
SL_GUNICORN_TIMEOUT_OVERRIDE=120

## Override max requests per worker
SL_MAX_REQUESTS_OVERRIDE=100

## Override database pool size
SL_DB_POOL_SIZE_OVERRIDE=3
```

### Container Memory Limits

Set maximum memory per container:

```bash
## Web application
SL_APP_MEMORY_LIMIT=512M
SL_APP_MEMORY_RESERVATION=128M

## Email handler
SL_EMAIL_MEMORY_LIMIT=256M
SL_EMAIL_MEMORY_RESERVATION=64M

## Job runner
SL_JOB_MEMORY_LIMIT=256M
SL_JOB_MEMORY_RESERVATION=64M

## Database
SL_DB_MEMORY_LIMIT=256M
SL_DB_MEMORY_RESERVATION=128M
```

### Example: 512MB RAM System

For a 512MB RAM VPS, use this `.env` configuration:

```bash
# Force low-memory mode
LOW_MEMORY_MODE=true

# Minimal workers
SL_GUNICORN_WORKERS_OVERRIDE=1

# Longer timeout for slow system
SL_GUNICORN_TIMEOUT_OVERRIDE=120

# Recycle workers frequently
SL_MAX_REQUESTS_OVERRIDE=100

# Small DB pool
SL_DB_POOL_SIZE_OVERRIDE=3

# Tight memory limits
SL_APP_MEMORY_LIMIT=256M
SL_APP_MEMORY_RESERVATION=128M
SL_EMAIL_MEMORY_LIMIT=128M
SL_EMAIL_MEMORY_RESERVATION=64M
SL_JOB_MEMORY_LIMIT=128M
SL_JOB_MEMORY_RESERVATION=64M
SL_DB_MEMORY_LIMIT=256M
SL_DB_MEMORY_RESERVATION=128M
```

## Monitoring and Tuning

### Check Current Configuration

View the resource dashboard:

```bash
bash scripts/detect-resources.sh
```

### Monitor Container Memory Usage

```bash
# Real-time monitoring
docker stats

# Check specific container
docker stats sl-app

# View memory limits
docker inspect sl-app | grep -A 10 Memory
```

### Check Container Logs

```bash
# Web app
docker logs sl-app --tail 100

# Email handler
docker logs sl-email --tail 100

# Job runner
docker logs sl-job-runner --tail 100

# Database
docker logs sl-db --tail 100
```

### Watch for OOM Conditions

```bash
# Check system memory
free -h

# Check Docker events for OOM kills
docker events --filter 'event=oom'

# Check system logs
dmesg | grep -i "out of memory"
```

### Performance Indicators

Good indicators that your system is properly tuned:

- ✅ All containers stay running
- ✅ No "worker timeout" errors
- ✅ Web interface responds (even if slow)
- ✅ Emails are processed (may be delayed)
- ✅ No OOM kills in logs

Warning signs of insufficient resources:

- ⚠️ Workers timing out frequently
- ⚠️ Containers restarting
- ⚠️ OOM killer messages in logs
- ⚠️ Database connection errors
- ⚠️ Very slow response times (> 30s)

## Troubleshooting

### Workers Timing Out

**Symptom:** "Worker timeout" errors in logs

**Solution:**
```bash
# Increase timeout in .env
SL_GUNICORN_TIMEOUT_OVERRIDE=180

# Reduce workers
SL_GUNICORN_WORKERS_OVERRIDE=1

# Restart
docker compose restart app
```

### Container Keeps Restarting

**Symptom:** Container status shows constant restarts

**Solution:**
```bash
# Check why it died
docker logs sl-app --tail 50

# If OOM, reduce memory usage
LOW_MEMORY_MODE=true
SL_APP_MEMORY_LIMIT=256M

# Restart
docker compose up -d
```

### Database Connection Errors

**Symptom:** "Too many connections" or connection failures

**Solution:**
```bash
# Reduce DB pool size
SL_DB_POOL_SIZE_OVERRIDE=3

# Increase DB memory limit
SL_DB_MEMORY_LIMIT=512M

# Restart all services
docker compose restart
```

### Very Slow Performance

**Symptom:** Everything works but is extremely slow

**Solution:**
```bash
# This is expected on low-resource systems
# To improve:

# 1. Enable swap (helps but slows down more)
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 2. Stop unnecessary services
docker compose stop job-runner  # If you don't need background jobs immediately

# 3. Increase timeout
SL_GUNICORN_TIMEOUT_OVERRIDE=300

# 4. Consider upgrading VPS
```

### Out of Memory Kills

**Symptom:** "Out of memory" in system logs, containers die

**Solution:**
```bash
# Enable forced low-memory mode
LOW_MEMORY_MODE=true

# Set aggressive memory limits
SL_APP_MEMORY_LIMIT=200M
SL_EMAIL_MEMORY_LIMIT=100M
SL_JOB_MEMORY_LIMIT=100M
SL_DB_MEMORY_LIMIT=200M

# Reduce all concurrent operations
SL_GUNICORN_WORKERS_OVERRIDE=1
SL_DB_POOL_SIZE_OVERRIDE=2

# Restart
docker compose down
docker compose up -d
```

### Emergency Recovery

If the system becomes completely unresponsive:

```bash
# 1. Stop everything
docker compose down

# 2. Free up memory
docker system prune -af

# 3. Enable swap if not already
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 4. Start with minimal configuration
LOW_MEMORY_MODE=true
SL_GUNICORN_WORKERS_OVERRIDE=1
docker compose up -d postgres
# Wait 30 seconds
docker compose up -d migration
docker compose up -d init
docker compose up -d app
```

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                     SimpleLogin Architecture                      │
│                  (Resource-Optimized Configuration)               │
└──────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ System Resources Detection                                       │
│ ┌─────────────┐  ┌─────────────┐  ┌──────────────┐            │
│ │  Total RAM  │  │ Avail. RAM  │  │  CPU Cores   │            │
│ └─────────────┘  └─────────────┘  └──────────────┘            │
│         │                │                  │                    │
│         └────────────────┴──────────────────┘                    │
│                          │                                       │
│                          ▼                                       │
│              ┌───────────────────────┐                          │
│              │ Resource Tier Decision│                          │
│              │  (CRITICAL/LOW/HIGH)  │                          │
│              └───────────────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ Dynamic Configuration                                            │
│                                                                  │
│  ┌────────────────────┐    ┌─────────────────────┐            │
│  │ Gunicorn Workers   │    │ Database Pool       │            │
│  │ • Count: 1-8       │    │ • Size: 3-20        │            │
│  │ • Timeout: 30-120s │    │ • Based on workers  │            │
│  │ • Max Reqs: varies │    └─────────────────────┘            │
│  └────────────────────┘                                         │
│                                                                  │
│  ┌────────────────────┐    ┌─────────────────────┐            │
│  │ Email Handler      │    │ Job Runner          │            │
│  │ • Threads: 1-4     │    │ • Threads: 1-3      │            │
│  └────────────────────┘    └─────────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ Container Deployment                                             │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   sl-app     │  │  sl-email    │  │ sl-job-runner│         │
│  │ Memory: 256M-│  │ Memory: 128M-│  │ Memory: 128M-│         │
│  │         1G   │  │         512M │  │         512M │         │
│  │ Workers: 1-8 │  │ Threads: 1-4 │  │ Threads: 1-3 │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │   sl-db      │  │   postfix    │                            │
│  │ Memory: 256M-│  │   (external) │                            │
│  │         512M │  │              │                            │
│  │ Pool: 3-20   │  │              │                            │
│  └──────────────┘  └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ Graceful Degradation                                             │
│                                                                  │
│  • OOM conditions caught and logged (not crashed)               │
│  • Workers recycled regularly to prevent memory leaks           │
│  • Timeouts extended on low-resource systems                    │
│  • Connection pools scaled to available memory                  │
│  • Background services throttled automatically                  │
└─────────────────────────────────────────────────────────────────┘
```

## Real-World Tuning Examples

### Example 1: DigitalOcean $6/month Droplet (1 vCPU, 1 GB RAM)

This works well with default automatic configuration:

```bash
# .env - no special configuration needed
# System will automatically detect and configure
```

**Expected Performance:**
- Web interface: 2-5 seconds response time
- Email processing: Nearly immediate
- Background jobs: Process within minutes
- Concurrent users: 5-10 users comfortably

### Example 2: Vultr $3.50/month VPS (1 vCPU, 512 MB RAM)

Requires low-memory mode:

```bash
# .env
LOW_MEMORY_MODE=true
SL_GUNICORN_WORKERS_OVERRIDE=1
SL_GUNICORN_TIMEOUT_OVERRIDE=120
SL_APP_MEMORY_LIMIT=256M
SL_DB_MEMORY_LIMIT=256M
```

**Expected Performance:**
- Web interface: 5-15 seconds response time
- Email processing: 1-2 minute delay
- Background jobs: Process within 5-10 minutes
- Concurrent users: 1-3 users

### Example 3: AWS t2.micro Free Tier (1 vCPU, 1 GB RAM)

Works with automatic mode, but may need swap:

```bash
# Enable swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# .env - use defaults or slight optimization
SL_APP_MEMORY_LIMIT=512M
SL_DB_MEMORY_LIMIT=512M
```

**Expected Performance:**
- Web interface: 3-8 seconds response time
- Email processing: Nearly immediate
- Background jobs: Process within minutes
- Concurrent users: 5-10 users

## Best Practices

1. **Always run preflight check first:**
   ```bash
   bash scripts/preflight-check.sh
   ```

2. **Monitor resource usage regularly:**
   ```bash
   docker stats
   free -h
   df -h
   ```

3. **Enable swap on low-RAM systems:**
   ```bash
   sudo fallocate -l 1G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

4. **Start with automatic mode, tune only if needed:**
   - Let the system auto-detect first
   - Monitor for a few days
   - Only add manual overrides if you see issues

5. **Keep database optimized:**
   ```bash
   # Weekly maintenance
   docker compose exec postgres vacuumdb -U $POSTGRES_USER -d $POSTGRES_DB -f -z
   ```

6. **Regular backups are critical on small VPS:**
   ```bash
   # Backup before any changes
   bash scripts/backup.sh  # If you create this
   ```

## Summary

SimpleLogin's dynamic resource optimization makes it possible to run on very small VPS instances:

- ✅ **512MB RAM minimum** - Fully functional in degraded mode
- ✅ **Automatic detection** - No manual configuration needed
- ✅ **Graceful degradation** - Never crashes, just slower
- ✅ **Manual overrides** - Full control when needed
- ✅ **Real-world tested** - Verified on popular VPS providers

The system prioritizes **reliability over performance** on resource-constrained systems, ensuring you always have a working email alias service, even if it's not the fastest.

---

**Last Updated:** 2026-02-02
