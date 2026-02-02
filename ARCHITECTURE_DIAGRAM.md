# SimpleLogin Dynamic Resource Optimization - Architecture Diagram

## System Overview

```
╔════════════════════════════════════════════════════════════════════════════════╗
║                    SimpleLogin Dynamic Resource Optimization                   ║
║                           Auto-Tuned Architecture                              ║
╚════════════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────────┐
│                            STARTUP PHASE                                      │
│                                                                              │
│  1. Container Start → 2. Detect Resources → 3. Calculate Config → 4. Apply  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Detailed Flow

### Phase 1: Resource Detection

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       SYSTEM RESOURCE DETECTION                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐           │
│  │  Read from   │     │  Read from   │     │    Count     │           │
│  │ /proc/meminfo│────▶│MemTotal      │     │  CPU Cores   │           │
│  │              │     │MemAvailable  │     │  (nproc)     │           │
│  └──────────────┘     └──────────────┘     └──────────────┘           │
│                              │                     │                    │
│                              ▼                     ▼                    │
│                     ┌─────────────────────────────────┐                │
│                     │   Resource Values Detected      │                │
│                     │                                 │                │
│                     │  • Total RAM: XXX MB            │                │
│                     │  • Available RAM: XXX MB        │                │
│                     │  • CPU Cores: X                 │                │
│                     └─────────────────────────────────┘                │
│                                  │                                      │
│                                  ▼                                      │
│                     ┌─────────────────────────────────┐                │
│                     │  Check LOW_MEMORY_MODE env var  │                │
│                     │  Override detection if set      │                │
│                     └─────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
```

### Phase 2: Configuration Calculation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DYNAMIC CONFIGURATION LOGIC                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  RAM Tier Decision:                                                     │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  if RAM < 256 MB   → CRITICAL  (Emergency, may not function)     │  │
│  │  if RAM < 768 MB   → LOW       (Degraded, minimal workers)       │  │
│  │  if RAM < 2048 MB  → MEDIUM    (Basic mode, limited features)    │  │
│  │  if RAM < 4096 MB  → HIGH      (Good performance)                │  │
│  │  if RAM >= 4096 MB → OPTIMAL   (Full features, max performance)  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  Component Configuration:                                               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  Gunicorn Workers:                                               │  │
│  │    Formula: min((2 * CPU_CORES + 1), RAM_LIMIT)                 │  │
│  │    • < 512 MB RAM  → 1 worker                                    │  │
│  │    • < 768 MB RAM  → 2 workers                                   │  │
│  │    • < 1024 MB RAM → 2 workers                                   │  │
│  │    • < 2048 MB RAM → 3 workers                                   │  │
│  │    • >= 2048 MB    → up to 8 workers                             │  │
│  │                                                                   │  │
│  │  Gunicorn Timeout:                                               │  │
│  │    • < 512 MB RAM  → 120 seconds (slow system)                   │  │
│  │    • < 1024 MB RAM → 90 seconds                                  │  │
│  │    • < 2048 MB RAM → 60 seconds                                  │  │
│  │    • >= 2048 MB    → 30 seconds (normal)                         │  │
│  │                                                                   │  │
│  │  Max Requests per Worker:                                        │  │
│  │    • < 512 MB RAM  → 100 (frequent recycling)                    │  │
│  │    • < 1024 MB RAM → 500                                         │  │
│  │    • < 2048 MB RAM → 1000                                        │  │
│  │    • >= 2048 MB    → 2000                                        │  │
│  │                                                                   │  │
│  │  Database Connection Pool:                                       │  │
│  │    Formula: min((workers + 2), RAM_LIMIT)                        │  │
│  │    • < 512 MB RAM  → 3 connections                               │  │
│  │    • < 1024 MB RAM → 5 connections                               │  │
│  │    • < 2048 MB RAM → 10 connections                              │  │
│  │    • >= 2048 MB    → 20 connections                              │  │
│  │                                                                   │  │
│  │  Background Service Threads:                                     │  │
│  │    Email Handler: 1-4 threads based on RAM/CPU                   │  │
│  │    Job Runner: 1-3 threads based on RAM/CPU                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
```

### Phase 3: Configuration Application

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CONFIGURATION APPLICATION                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    Check Manual Overrides                         │ │
│  │                                                                   │ │
│  │  Environment Variables (from .env):                              │ │
│  │    • SL_GUNICORN_WORKERS_OVERRIDE                                │ │
│  │    • SL_GUNICORN_TIMEOUT_OVERRIDE                                │ │
│  │    • SL_MAX_REQUESTS_OVERRIDE                                    │ │
│  │    • SL_DB_POOL_SIZE_OVERRIDE                                    │ │
│  │                                                                   │ │
│  │  If set: Use override value                                      │ │
│  │  If not set: Use calculated value                                │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                              │                                         │
│                              ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                Export Final Configuration                         │ │
│  │                                                                   │ │
│  │  export SL_GUNICORN_WORKERS=X                                    │ │
│  │  export SL_GUNICORN_TIMEOUT=Y                                    │ │
│  │  export SL_MAX_REQUESTS=Z                                        │ │
│  │  export SL_DB_POOL_SIZE=W                                        │ │
│  └───────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
```

### Phase 4: Service Startup

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SERVICE DEPLOYMENT                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                         sl-app Container                        │    │
│  │                                                                 │    │
│  │  Entrypoint: resource-optimized-entrypoint.sh app              │    │
│  │                                                                 │    │
│  │  1. Detect resources → detect-resources.sh                     │    │
│  │  2. Show dashboard                                             │    │
│  │  3. Build Gunicorn command:                                    │    │
│  │     gunicorn wsgi:app \                                        │    │
│  │       -b 0.0.0.0:7777 \                                        │    │
│  │       -w $SL_GUNICORN_WORKERS \                                │    │
│  │       --timeout $SL_GUNICORN_TIMEOUT \                         │    │
│  │       --max-requests $SL_MAX_REQUESTS \                        │    │
│  │       --max-requests-jitter $(($SL_MAX_REQUESTS / 10))         │    │
│  │  4. Start application                                          │    │
│  │                                                                 │    │
│  │  Memory Limits:                                                │    │
│  │    • Limit: ${SL_APP_MEMORY_LIMIT:-1G}                         │    │
│  │    • Reservation: ${SL_APP_MEMORY_RESERVATION:-256M}           │    │
│  │                                                                 │    │
│  │  OOM Protection:                                               │    │
│  │    • trap TERM signal                                          │    │
│  │    • Log OOM condition                                         │    │
│  │    • Graceful shutdown (exit 137)                              │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                      sl-email Container                         │    │
│  │                                                                 │    │
│  │  Entrypoint: resource-optimized-entrypoint.sh email            │    │
│  │                                                                 │    │
│  │  1. Detect resources                                           │    │
│  │  2. Start: python email_handler.py                            │    │
│  │     • Threads scaled by $SL_EMAIL_THREADS                      │    │
│  │                                                                 │    │
│  │  Memory Limits:                                                │    │
│  │    • Limit: ${SL_EMAIL_MEMORY_LIMIT:-512M}                     │    │
│  │    • Reservation: ${SL_EMAIL_MEMORY_RESERVATION:-128M}         │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                    sl-job-runner Container                      │    │
│  │                                                                 │    │
│  │  Entrypoint: resource-optimized-entrypoint.sh job-runner       │    │
│  │                                                                 │    │
│  │  1. Detect resources                                           │    │
│  │  2. Start: python job_runner.py                               │    │
│  │     • Threads scaled by $SL_JOB_THREADS                        │    │
│  │                                                                 │    │
│  │  Memory Limits:                                                │    │
│  │    • Limit: ${SL_JOB_MEMORY_LIMIT:-512M}                       │    │
│  │    • Reservation: ${SL_JOB_MEMORY_RESERVATION:-128M}           │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                        sl-db Container                          │    │
│  │                                                                 │    │
│  │  PostgreSQL 12.1                                               │    │
│  │                                                                 │    │
│  │  Connection pool sized by configuration:                       │    │
│  │    max_connections = $SL_DB_POOL_SIZE                          │    │
│  │                                                                 │    │
│  │  Memory Limits:                                                │    │
│  │    • Limit: ${SL_DB_MEMORY_LIMIT:-512M}                        │    │
│  │    • Reservation: ${SL_DB_MEMORY_RESERVATION:-256M}            │    │
│  └────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
```

### Phase 5: Runtime Protection

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RUNTIME PROTECTION                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Graceful Degradation Mechanisms:                                       │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  1. Worker Recycling                                             │ │
│  │     • Workers restart after max_requests                         │ │
│  │     • Prevents memory leak accumulation                          │ │
│  │     • More frequent on low-RAM systems                           │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  2. OOM Detection                                                │ │
│  │     • trap TERM signal in entrypoint                             │ │
│  │     • Log detailed error message                                 │ │
│  │     • Provide troubleshooting suggestions                        │ │
│  │     • Exit gracefully (137) instead of crash                     │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  3. Docker Memory Limits                                         │ │
│  │     • Hard limits prevent system-wide OOM                        │ │
│  │     • Reservations ensure minimum resources                      │ │
│  │     • Container-level isolation                                  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  4. Extended Timeouts                                            │ │
│  │     • Longer timeouts on low-resource systems                    │ │
│  │     • Prevents premature worker kills                            │ │
│  │     • Allows slow operations to complete                         │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  5. Connection Pool Scaling                                      │ │
│  │     • Pools sized to match worker count                          │ │
│  │     • Prevents connection exhaustion                             │ │
│  │     • Reduces DB memory overhead                                 │ │
│  └───────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

## Example Configurations

### Low-Resource VPS (512MB RAM, 1 vCPU)

```
┌─────────────────────────────────────────────────────────────────┐
│                  LOW-RESOURCE CONFIGURATION                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  System Resources:                                              │
│    • Total RAM: 512 MB                                          │
│    • Available RAM: ~400 MB                                     │
│    • CPU Cores: 1                                               │
│    • Tier: LOW (Degraded Mode)                                  │
│                                                                  │
│  Calculated Configuration:                                      │
│    • Gunicorn Workers: 1                                        │
│    • Gunicorn Timeout: 120 seconds                              │
│    • Max Requests: 100                                          │
│    • DB Pool Size: 3                                            │
│    • Email Threads: 1                                           │
│    • Job Threads: 1                                             │
│                                                                  │
│  Memory Allocation:                                             │
│    • sl-app: 256M (50%)                                         │
│    • sl-db: 256M (50%)                                          │
│    • sl-email: Shared with app                                  │
│    • sl-job-runner: Shared with app                             │
│                                                                  │
│  Expected Performance:                                          │
│    • Web Response: 5-15 seconds                                 │
│    • Email Processing: 1-2 minute delay                         │
│    • Background Jobs: 5-10 minutes                              │
│    • Concurrent Users: 1-3                                      │
└─────────────────────────────────────────────────────────────────┘
```

### Standard VPS (2GB RAM, 2 vCPU)

```
┌─────────────────────────────────────────────────────────────────┐
│                  STANDARD CONFIGURATION                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  System Resources:                                              │
│    • Total RAM: 2048 MB                                         │
│    • Available RAM: ~1600 MB                                    │
│    • CPU Cores: 2                                               │
│    • Tier: MEDIUM (Basic Mode)                                  │
│                                                                  │
│  Calculated Configuration:                                      │
│    • Gunicorn Workers: 3                                        │
│    • Gunicorn Timeout: 60 seconds                               │
│    • Max Requests: 1000                                         │
│    • DB Pool Size: 10                                           │
│    • Email Threads: 2                                           │
│    • Job Threads: 2                                             │
│                                                                  │
│  Memory Allocation:                                             │
│    • sl-app: 1G (50%)                                           │
│    • sl-db: 512M (25%)                                          │
│    • sl-email: 256M (12.5%)                                     │
│    • sl-job-runner: 256M (12.5%)                                │
│                                                                  │
│  Expected Performance:                                          │
│    • Web Response: 2-5 seconds                                  │
│    • Email Processing: Nearly immediate                         │
│    • Background Jobs: Within minutes                            │
│    • Concurrent Users: 10-20                                    │
└─────────────────────────────────────────────────────────────────┘
```

### High-Performance Server (8GB RAM, 4 vCPU)

```
┌─────────────────────────────────────────────────────────────────┐
│               HIGH-PERFORMANCE CONFIGURATION                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  System Resources:                                              │
│    • Total RAM: 8192 MB                                         │
│    • Available RAM: ~7000 MB                                    │
│    • CPU Cores: 4                                               │
│    • Tier: OPTIMAL                                              │
│                                                                  │
│  Calculated Configuration:                                      │
│    • Gunicorn Workers: 8                                        │
│    • Gunicorn Timeout: 30 seconds                               │
│    • Max Requests: 2000                                         │
│    • DB Pool Size: 20                                           │
│    • Email Threads: 4                                           │
│    • Job Threads: 3                                             │
│                                                                  │
│  Memory Allocation:                                             │
│    • sl-app: 4G (50%)                                           │
│    • sl-db: 2G (25%)                                            │
│    • sl-email: 1G (12.5%)                                       │
│    • sl-job-runner: 1G (12.5%)                                  │
│                                                                  │
│  Expected Performance:                                          │
│    • Web Response: < 2 seconds                                  │
│    • Email Processing: Instant                                  │
│    • Background Jobs: Real-time                                 │
│    • Concurrent Users: 50+                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Decision Tree

```
                    ┌─────────────────────┐
                    │   Container Start   │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  Detect RAM/CPU     │
                    └──────────┬──────────┘
                               │
                ┌──────────────┴──────────────┐
                │                             │
                ▼                             ▼
         ┌──────────────┐            ┌──────────────┐
         │ LOW_MEMORY   │            │   Normal     │
         │  MODE=true?  │            │  Detection   │
         └──────┬───────┘            └──────┬───────┘
                │ Yes                       │ No
                ▼                           │
         ┌──────────────┐                  │
         │ Force 512MB  │                  │
         │ calculations │                  │
         └──────┬───────┘                  │
                │                           │
                └───────────┬───────────────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │ Calculate RAM Tier   │
                 └──────────┬───────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
    ┌─────────┐       ┌─────────┐      ┌─────────┐
    │CRITICAL │       │   LOW   │      │ MEDIUM+ │
    │< 256 MB │       │< 768 MB │      │>= 768MB │
    └────┬────┘       └────┬────┘      └────┬────┘
         │                 │                 │
         ▼                 ▼                 ▼
    ┌─────────┐       ┌─────────┐      ┌─────────┐
    │  Exit   │       │Minimal  │      │ Normal  │
    │  with   │       │Workers  │      │Workers  │
    │ Warning │       │Longer   │      │Standard │
    │         │       │Timeouts │      │Timeouts │
    └─────────┘       └────┬────┘      └────┬────┘
                           │                 │
                           └────────┬────────┘
                                    │
                                    ▼
                          ┌─────────────────┐
                          │ Check Overrides │
                          └────────┬────────┘
                                   │
                                   ▼
                          ┌─────────────────┐
                          │ Apply Config &  │
                          │ Start Service   │
                          └─────────────────┘
```

---

## Key Features

### 1. Automatic Detection
- No manual configuration required
- Detects RAM, CPU at runtime
- Adjusts all components dynamically

### 2. Graceful Degradation
- Never crashes from resource exhaustion
- Automatically reduces features when needed
- Maintains core functionality always

### 3. Manual Override
- All settings can be overridden via .env
- Supports both automatic and manual modes
- Flexible for advanced users

### 4. OOM Protection
- Traps OOM conditions
- Logs detailed diagnostics
- Graceful shutdown instead of crash

### 5. Memory Isolation
- Docker memory limits per container
- Prevents system-wide OOM
- Predictable resource usage

---

**Last Updated:** 2026-02-02
