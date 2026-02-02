# Worker Timeout Investigation Tools

This directory contains comprehensive tools for investigating, monitoring, and preventing Gunicorn worker timeout issues in SimpleLogin.

## Tools Overview

### 1. test-ram-scenarios.sh
**Purpose:** Systematic testing across different RAM configurations

**What it does:**
- Tests SimpleLogin at 256MB, 512MB, 768MB, 1GB, 2GB, 4GB, 8GB RAM
- Simulates memory constraints using Docker limits
- Records startup times, timeout rates, and performance
- Generates test matrix CSV and comprehensive reports
- Documents root causes for each RAM tier

**Usage:**
```bash
# Run full test suite with Docker memory limits
./test-ram-scenarios.sh --docker

# Generate report from previous test results
./test-ram-scenarios.sh --report-only
```

**Output:**
- `test-results/test-TIMESTAMP.log` - Detailed test log
- `test-results/test-matrix-TIMESTAMP.csv` - Test matrix data
- `test-results/TEST_REPORT_TIMESTAMP.md` - Comprehensive report

**When to use:**
- Validating worker timeout fixes
- Testing new resource optimization changes
- Documenting system behavior at different RAM levels
- Troubleshooting resource-related issues

---

### 2. instrument-worker-lifecycle.sh
**Purpose:** Real-time worker lifecycle monitoring and analysis

**What it does:**
- Monitors Docker logs for worker events
- Tracks worker spawn, timeout, exit, restart events
- Detects out-of-memory conditions
- Logs resource information at startup
- Analyzes worker health patterns

**Usage:**
```bash
# Start monitoring
./instrument-worker-lifecycle.sh start

# Check monitoring status
./instrument-worker-lifecycle.sh status

# View live logs
./instrument-worker-lifecycle.sh tail

# Stop monitoring and analyze
./instrument-worker-lifecycle.sh stop

# Analyze existing log file
./instrument-worker-lifecycle.sh analyze path/to/logfile.log
```

**Output:**
- `instrumentation-logs/worker-lifecycle-TIMESTAMP.log` - Event log
- `instrumentation-logs/worker-lifecycle-TIMESTAMP-ANALYSIS.txt` - Analysis report

**Events Tracked:**
- 🚀 WORKER_SPAWN - New worker starting
- ⏱️ WORKER_TIMEOUT - Worker timeout detected
- 💀 WORKER_EXIT - Worker terminated
- 💥 OOM_DETECTED - Out of memory condition
- 👂 READY - Service ready to accept requests
- 🔄 WORKER_RESTART - Worker restarting
- ❌ ERROR - Error detected

**When to use:**
- Debugging worker timeout issues
- Understanding worker lifecycle behavior
- Collecting data for troubleshooting
- Validating configuration changes

---

### 3. monitor-worker-health.sh
**Purpose:** Real-time worker health monitoring dashboard

**What it does:**
- Displays live dashboard with worker health status
- Shows CPU and memory usage
- Tracks worker events (timeouts, restarts, OOM)
- Provides health assessment and recommendations
- Updates every 5 seconds (configurable)

**Usage:**
```bash
# Start monitoring with default 5-second interval
./monitor-worker-health.sh

# Use custom check interval (10 seconds)
./monitor-worker-health.sh 10

# Enable alerts on timeout detection
./monitor-worker-health.sh 5 true
```

**Dashboard Sections:**
1. **Container Resources**
   - CPU usage with status indicator
   - Memory usage with status indicator
   
2. **Worker Configuration**
   - Number of workers
   - Timeout setting

3. **Worker Health (Last 60s)**
   - Worker timeouts count
   - Worker restarts count
   - OOM events count
   - Error count

4. **Health Assessment**
   - Overall health status
   - Recommendations for issues

**When to use:**
- Real-time monitoring of production systems
- Detecting worker timeout issues as they occur
- Validating configuration changes
- Quick health checks

**Example Dashboard:**
```
╔════════════════════════════════════════════════════════════════╗
║         SimpleLogin Worker Health Monitoring Dashboard         ║
╚════════════════════════════════════════════════════════════════╝

2026-02-02 02:45:30  |  Iteration: 5  |  Interval: 5s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━ CONTAINER RESOURCES ━━━
  CPU Usage:      25.5%               [NORMAL]
  Memory Usage:   450MiB / 1GiB      [NORMAL]

━━━ WORKER CONFIGURATION ━━━
  Workers:        2
  Timeout:        60s

━━━ WORKER HEALTH (Last 60s) ━━━
  Worker Timeouts:    0  [OK]
  Worker Restarts:    0  [NONE]
  OOM Events:         0  [NONE]
  Errors:             0  [NONE]

━━━ HEALTH ASSESSMENT ━━━
  Status: ✓ HEALTHY
  Workers are operating normally

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Press Ctrl+C to exit
```

---

### 4. detect-resources.sh (Existing)
**Purpose:** Automatic resource detection and configuration

**What it does:**
- Detects total and available RAM
- Detects CPU core count
- Calculates optimal worker count, timeout, and DB pool size
- Displays resource dashboard at startup
- Exports configuration as environment variables

**Usage:**
```bash
# Show resource dashboard (human-readable)
./detect-resources.sh

# Export as environment variables
./detect-resources.sh --export

# Output as JSON
./detect-resources.sh --json
```

**Integrated Into:**
- Container startup via `resource-optimized-entrypoint.sh`
- Preflight checks via `preflight-check.sh`

**When to use:**
- Checking current resource configuration
- Understanding auto-detected settings
- Debugging resource detection issues
- Validating manual overrides

---

### 5. resource-optimized-entrypoint.sh (Existing)
**Purpose:** Container entrypoint with dynamic resource configuration

**What it does:**
- Runs resource detection at container startup
- Applies optimal configuration for detected resources
- Handles manual overrides from environment
- Provides graceful OOM handling
- Logs all configuration decisions

**Usage:**
Used automatically by Docker Compose services:
```yaml
services:
  app:
    entrypoint: ["/scripts/resource-optimized-entrypoint.sh", "app"]
```

**When to use:**
- Always used automatically
- No manual invocation needed
- Review logs to see applied configuration

---

## Quick Start Guide

### Investigating Worker Timeouts

1. **Check Current Health:**
   ```bash
   ./monitor-worker-health.sh
   ```
   Watch for timeout, restart, or OOM events

2. **Instrument Lifecycle:**
   ```bash
   ./instrument-worker-lifecycle.sh start
   # Let it run for 5-10 minutes
   ./instrument-worker-lifecycle.sh stop
   ```
   Review analysis for patterns

3. **Check Resource Configuration:**
   ```bash
   ./detect-resources.sh
   ```
   Verify detected configuration is appropriate

4. **Run Comprehensive Tests:**
   ```bash
   ./test-ram-scenarios.sh
   ```
   Validate system behavior across scenarios

### Validating a Fix

1. **Baseline Test:**
   ```bash
   ./test-ram-scenarios.sh --docker > before.log
   ```

2. **Apply Configuration Changes:**
   ```bash
   # Edit .env with new settings
   docker compose restart app
   ```

3. **Validation Test:**
   ```bash
   ./test-ram-scenarios.sh --docker > after.log
   ```

4. **Monitor Runtime:**
   ```bash
   ./monitor-worker-health.sh
   ```
   Watch for 30-60 minutes

5. **Compare Results:**
   ```bash
   diff before.log after.log
   ```

### Regular Health Monitoring

**Daily Check:**
```bash
./monitor-worker-health.sh
# Let it run for 5 minutes
# Ctrl+C to exit
```

**Weekly Deep Dive:**
```bash
./instrument-worker-lifecycle.sh start
# Let it run for 24 hours
./instrument-worker-lifecycle.sh stop
# Review analysis report
```

**Monthly Validation:**
```bash
./test-ram-scenarios.sh --report-only
# Review test report
# Compare with previous months
```

---

## Troubleshooting

### Tool Not Working

**Problem:** Script fails to execute
```bash
# Make scripts executable
chmod +x scripts/*.sh
```

**Problem:** Container not found
```bash
# Check container is running
docker ps | grep sl-app

# Start if needed
docker compose up -d app
```

### Understanding Results

**Worker Timeouts Detected:**
1. Check RAM configuration: `./detect-resources.sh`
2. Increase timeout: Add `SL_GUNICORN_TIMEOUT_OVERRIDE=120` to `.env`
3. Reduce workers: Add `SL_GUNICORN_WORKERS_OVERRIDE=1` to `.env`
4. Restart: `docker compose restart app`

**OOM Events Detected:**
1. Enable low-memory mode: `LOW_MEMORY_MODE=true` in `.env`
2. Reduce memory limits in `.env`
3. Add swap space to system
4. Consider RAM upgrade

**High Restart Rate:**
1. Check application logs: `docker logs sl-app`
2. Look for error patterns
3. May indicate memory leaks
4. Review application code

---

## Integration with Existing Tools

### With Docker Compose
```bash
# View container logs with our monitoring
docker compose logs -f app | grep -E "WORKER_|OOM_|TIMEOUT"
```

### With diagnose.sh
```bash
# Run diagnostics, then instrument
./diagnose.sh
./instrument-worker-lifecycle.sh start
# Let run for analysis period
./instrument-worker-lifecycle.sh stop
```

### With preflight-check.sh
```bash
# Preflight check runs detect-resources.sh automatically
./preflight-check.sh

# For deeper validation, follow with:
./test-ram-scenarios.sh
```

---

## Output Directory Structure

```
project/
├── test-results/
│   ├── test-TIMESTAMP.log
│   ├── test-matrix-TIMESTAMP.csv
│   └── TEST_REPORT_TIMESTAMP.md
├── instrumentation-logs/
│   ├── worker-lifecycle-TIMESTAMP.log
│   └── worker-lifecycle-TIMESTAMP-ANALYSIS.txt
└── scripts/
    ├── test-ram-scenarios.sh
    ├── instrument-worker-lifecycle.sh
    ├── monitor-worker-health.sh
    ├── detect-resources.sh
    └── resource-optimized-entrypoint.sh
```

---

## Best Practices

1. **Regular Monitoring:**
   - Run health dashboard weekly
   - Instrument lifecycle monthly
   - Full test suite before major changes

2. **Keep Logs:**
   - Archive instrumentation logs
   - Compare trends over time
   - Document configuration changes

3. **Test Before Production:**
   - Run test suite on staging
   - Validate with instrumentation
   - Monitor for 24 hours before promoting

4. **Document Findings:**
   - Record timeout patterns
   - Note configuration changes
   - Share insights with team

---

## Related Documentation

- [ROOT_CAUSE_ANALYSIS.md](../ROOT_CAUSE_ANALYSIS.md) - Technical deep dive
- [PERFORMANCE_BENCHMARKS.md](../PERFORMANCE_BENCHMARKS.md) - Measured results
- [INVESTIGATION_SUMMARY.md](../INVESTIGATION_SUMMARY.md) - Investigation overview
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Common issues
- [LOW_RESOURCE_GUIDE.md](../LOW_RESOURCE_GUIDE.md) - Low-RAM guidance

---

**Last Updated:** 2026-02-02  
**Maintained By:** SimpleLogin Self-Hosted Community
