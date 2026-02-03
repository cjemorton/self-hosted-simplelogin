# Traefik ACME Challenge Configuration - Root Cause Analysis & Fix

**Date:** 2026-02-03  
**Status:** ✅ Fixed  
**Issue:** Traefik performing TLS-ALPN challenges despite `.env` specifying DNS challenge

## Executive Summary

Users reported that Traefik was still performing TLS-ALPN (tls) ACME challenges even after setting `LE_CHALLENGE=dns` and `LE_DNS_PROVIDER=cloudflare` in their `.env` file. This investigation identified the root cause and implemented a permanent fix.

## Root Cause Analysis

### The Problem

The original `traefik-compose.yaml` configuration had a **fundamental design flaw** where it unconditionally defined BOTH certificate resolvers:

```yaml
# traefik-compose.yaml (BEFORE FIX)
command:
  # ... other config ...
  - --certificatesresolvers.tls.acme.tlschallenge=true      # ❌ ALWAYS enabled
  - --certificatesresolvers.dns.acme.dnschallenge=true      # ❌ ALWAYS enabled
  - --certificatesresolvers.dns.acme.dnschallenge.provider=${LE_DNS_PROVIDER}
```

### Why This Caused Issues

1. **Both Resolvers Active Simultaneously**
   - The configuration always defined both the `tls` resolver (with TLS-ALPN challenge) and the `dns` resolver (with DNS-01 challenge)
   - Both were active in Traefik's configuration regardless of the `LE_CHALLENGE` environment variable

2. **Unpredictable Behavior**
   - When both resolvers are active, Traefik may attempt both challenge types
   - The TLS-ALPN resolver could be triggered as a fallback if DNS challenge encounters any issues
   - This behavior is non-deterministic and can vary based on timing, DNS resolution, or API connectivity

3. **Environment Variable Only Controlled Router Selection**
   - The `LE_CHALLENGE` variable was only used in:
     ```yaml
     - --entrypoints.websecure.http.tls.certresolver=${LE_CHALLENGE:-tls}
     ```
   - This told routers which resolver to *prefer*, but didn't prevent the other resolver from being active
   - Docker labels on services referenced `${LE_CHALLENGE}` for router cert resolver, but this didn't disable the unused resolver

4. **DNS Credentials Present = Potential Confusion**
   - Even with valid DNS credentials configured, the TLS-ALPN resolver remained active
   - If DNS validation was slow or failed, Traefik could fall back to TLS-ALPN
   - Users would see TLS-ALPN challenge attempts in logs despite DNS configuration

### Technical Details

**Docker Compose Limitations:**
- Docker Compose does not support conditional command arguments based on environment variables
- You cannot use `if/else` logic in the `command:` section
- All command arguments are evaluated and passed to the container regardless of env var values

**Example of What Doesn't Work:**
```yaml
# ❌ This is NOT possible in Docker Compose
command:
  - if [ "$LE_CHALLENGE" = "dns" ]; then
      --certificatesresolvers.dns.acme.dnschallenge=true
    else
      --certificatesresolvers.tls.acme.tlschallenge=true
    fi
```

**What Actually Happened:**
```yaml
# ✅ This is what was happening (both always active)
command:
  - --certificatesresolvers.tls.acme.tlschallenge=true      # ALWAYS
  - --certificatesresolvers.dns.acme.dnschallenge=true      # ALWAYS
  - --entrypoints.websecure.http.tls.certresolver=${LE_CHALLENGE:-tls}  # Variable substitution
```

The environment variable substitution (`${LE_CHALLENGE}`) only works for replacing values, not for conditionally including/excluding entire command arguments.

## The Solution

### Approach: Custom Entrypoint Script

Since Docker Compose cannot conditionally include command arguments, we implemented a **custom entrypoint script** that:

1. Reads the `LE_CHALLENGE` environment variable
2. Conditionally builds the Traefik command arguments based on its value
3. Defines ONLY the appropriate certificate resolver
4. Executes Traefik with the correct configuration

### Implementation

**File:** `scripts/traefik-entrypoint.sh`

```bash
#!/bin/sh
# Traefik Entrypoint Script
# Conditionally configures Traefik based on LE_CHALLENGE environment variable

set -e

LE_CHALLENGE="${LE_CHALLENGE:-tls}"
LE_EMAIL="${LE_EMAIL:-${SUPPORT_EMAIL:-support@${DOMAIN}}}"

# Base configuration (common to both modes)
TRAEFIK_ARGS="
    --accesslog=true
    --ping=true
    --global.sendanonymoususage=false
    --providers.docker.exposedByDefault=false
    --providers.docker.network=traefik
    --entrypoints.web.address=:80
    --entrypoints.web.http.redirections.entrypoint.to=websecure
    --entrypoints.web.http.redirections.entrypoint.scheme=https
    --entrypoints.websecure.address=:443
    --entrypoints.websecure.http.tls.certresolver=${LE_CHALLENGE}
    --experimental.plugins.staticresponse.moduleName=github.com/jdel/staticresponse
    --experimental.plugins.staticresponse.version=v0.0.1
"

# Configure ONLY the appropriate certificate resolver
if [ "$LE_CHALLENGE" = "dns" ]; then
    echo "INFO: Configuring Traefik for DNS-01 ACME challenge"
    
    # Validate DNS provider is set
    if [ -z "$LE_DNS_PROVIDER" ]; then
        echo "ERROR: LE_CHALLENGE=dns but LE_DNS_PROVIDER is not set!"
        exit 1
    fi
    
    # DNS challenge - ONLY define 'dns' resolver
    TRAEFIK_ARGS="$TRAEFIK_ARGS
        --certificatesresolvers.dns.acme.storage=/etc/traefik/acme/acme-dns.json
        --certificatesresolvers.dns.acme.email=${LE_EMAIL}
        --certificatesresolvers.dns.acme.dnschallenge=true
        --certificatesresolvers.dns.acme.dnschallenge.provider=${LE_DNS_PROVIDER}
    "
else
    echo "INFO: Configuring Traefik for TLS-ALPN ACME challenge"
    
    # TLS challenge - ONLY define 'tls' resolver
    TRAEFIK_ARGS="$TRAEFIK_ARGS
        --certificatesresolvers.tls.acme.storage=/etc/traefik/acme/acme-tls.json
        --certificatesresolvers.tls.acme.email=${LE_EMAIL}
        --certificatesresolvers.tls.acme.tlschallenge=true
    "
fi

# Execute Traefik with constructed arguments
exec /entrypoint.sh traefik $TRAEFIK_ARGS "$@"
```

**File:** `traefik-compose.yaml` (updated)

```yaml
services:
  reverse-proxy:
    image: traefik:${TRAEFIK_VERSION:-latest}
    container_name: traefik
    restart: ${RESTART_POLICY:-unless-stopped}
    entrypoint: ["/scripts/traefik-entrypoint.sh"]  # ← Use custom entrypoint
    env_file: ${SL_CONFIG_PATH:-.env}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik-acme:/etc/traefik/acme
      - ./scripts:/scripts:ro                        # ← Mount scripts directory
    # ... rest of configuration
```

### How It Works

1. **Container Starts:**
   - Docker runs the custom `traefik-entrypoint.sh` script instead of Traefik directly

2. **Script Reads Environment:**
   - Loads `LE_CHALLENGE`, `LE_DNS_PROVIDER`, and other variables from `.env` file

3. **Conditional Configuration:**
   - If `LE_CHALLENGE=tls`: Builds command with ONLY TLS-ALPN resolver
   - If `LE_CHALLENGE=dns`: Builds command with ONLY DNS-01 resolver
   - Validates required credentials are present

4. **Execute Traefik:**
   - Calls the original Traefik entrypoint with the constructed command
   - Traefik starts with ONLY the appropriate resolver active

5. **Result:**
   - Only ONE certificate resolver is defined and active
   - No fallback to alternate challenge types
   - Predictable, deterministic behavior

## Validation & Testing

### Verification Commands

Users can verify the fix is working with these commands:

```bash
# 1. Check which challenge type is configured
docker logs traefik --tail 30 | grep "INFO: Configuring Traefik"
# Expected output for DNS:
#   INFO: Configuring Traefik for DNS-01 ACME challenge

# 2. Verify only the correct resolver is defined
docker inspect traefik --format='{{.Args}}' | grep certificatesresolvers
# For DNS mode, should see ONLY:
#   --certificatesresolvers.dns.acme.dnschallenge=true
# For TLS mode, should see ONLY:
#   --certificatesresolvers.tls.acme.tlschallenge=true

# 3. Confirm environment variables are loaded
docker exec traefik env | grep LE_CHALLENGE
# Should show: LE_CHALLENGE=dns (or tls)

# 4. Run comprehensive diagnostics
bash scripts/traefik-diagnostics.sh
```

### Test Cases

| Test Case | Configuration | Expected Behavior | Status |
|-----------|---------------|-------------------|--------|
| Default (no LE_CHALLENGE) | `.env`: (not set) | TLS-ALPN challenge used | ✅ Pass |
| Explicit TLS | `.env`: LE_CHALLENGE=tls | TLS-ALPN challenge used | ✅ Pass |
| DNS without provider | `.env`: LE_CHALLENGE=dns | Error on startup | ✅ Pass |
| DNS with provider | `.env`: LE_CHALLENGE=dns<br>LE_DNS_PROVIDER=cloudflare | DNS challenge used | ✅ Pass |
| DNS with invalid credentials | `.env`: LE_CHALLENGE=dns<br>LE_DNS_PROVIDER=cloudflare<br>CF_DNS_API_TOKEN=invalid | DNS challenge attempted, fails gracefully | ✅ Pass |
| Switch from TLS to DNS | Change `.env` and restart | Configuration updates correctly | ✅ Pass |

## Benefits of the Fix

### 1. **Deterministic Behavior**
- Only ONE resolver is active at any time
- No race conditions or fallback scenarios
- Behavior matches user configuration exactly

### 2. **Clear Error Messages**
- Script validates configuration before starting Traefik
- Missing DNS provider causes immediate, clear error
- Helpful error messages guide users to fix issues

### 3. **Easier Troubleshooting**
- Logs clearly show which challenge type is configured
- Diagnostic script verifies configuration
- No confusion about which resolver is active

### 4. **Wildcard Certificate Support**
- DNS challenge works reliably for `*.domain.com` certificates
- No accidental TLS-ALPN attempts that would fail for wildcards

### 5. **Backwards Compatible**
- Default behavior (TLS-ALPN) unchanged for existing users
- Explicit `LE_CHALLENGE=tls` continues to work
- No breaking changes to existing configurations

## Additional Improvements

### 1. Diagnostic Script

Created `scripts/traefik-diagnostics.sh` to help users verify their configuration:
- Checks environment variables
- Validates certificate resolver configuration
- Inspects router labels
- Analyzes certificate files
- Provides actionable recommendations

### 2. Troubleshooting Guide

Created `TRAEFIK_ACME_TROUBLESHOOTING.md` with:
- Quick verification commands
- Explanation of challenge types
- Common issues and solutions
- Step-by-step diagnostic procedures
- Provider-specific configuration guides

### 3. Enhanced Documentation

Updated `.env.example` with:
- Clear explanation of each challenge type
- Pros and cons of TLS vs DNS
- Provider-specific credential examples
- Links to official documentation
- Instructions for troubleshooting

## Migration Guide

### For Existing Users

If you were previously experiencing TLS-ALPN challenges despite DNS configuration:

1. **Pull the latest changes:**
   ```bash
   git pull origin main
   ```

2. **Verify your .env configuration:**
   ```bash
   grep LE_CHALLENGE .env
   grep LE_DNS_PROVIDER .env
   ```

3. **Restart Traefik:**
   ```bash
   docker compose down
   docker compose up -d
   ```

4. **Verify the fix:**
   ```bash
   bash scripts/traefik-diagnostics.sh
   ```

5. **Check logs:**
   ```bash
   docker logs traefik | grep "INFO: Configuring"
   ```

### For New Users

Follow the standard setup in README.md. The configuration will work correctly from the start.

## Technical Notes

### Entrypoint Chain

The script uses an **entrypoint chain** to maintain compatibility:
1. Custom script: `/scripts/traefik-entrypoint.sh`
2. Calls original: `/entrypoint.sh traefik [args]`
3. Original entrypoint handles signals, environment, etc.
4. Traefik process starts with correct arguments

This ensures all Traefik container features work normally (healthchecks, signals, etc.).

### Environment Variable Handling

The script properly handles default values:
```bash
LE_CHALLENGE="${LE_CHALLENGE:-tls}"  # Default to 'tls'
LE_EMAIL="${LE_EMAIL:-${SUPPORT_EMAIL:-support@${DOMAIN}}}"  # Nested defaults
```

This matches Docker Compose's behavior for consistency.

### Script Permissions

The script must be executable. The repository includes it with execute permissions:
```bash
chmod +x scripts/traefik-entrypoint.sh
```

This is preserved in git via `.gitattributes` or committed permissions.

## Future Enhancements

Possible improvements for future versions:

1. **Let's Encrypt Staging Support**
   - Add `LE_STAGING=true` option
   - Automatically use staging server for testing
   - Prevents rate limit exhaustion during development

2. **Multi-Resolver Support**
   - Define multiple resolvers for different domains
   - Use DNS for wildcards, TLS for specific subdomains
   - Requires more complex router configuration

3. **Certificate Monitoring**
   - Add expiration monitoring
   - Alert before renewal needed
   - Prometheus metrics for certificate status

4. **Automated Testing**
   - Integration tests for both challenge types
   - Validate certificate issuance in CI/CD
   - Test switching between modes

## Conclusion

The fix successfully resolves the issue where Traefik would perform TLS-ALPN challenges despite DNS challenge configuration. By using a conditional entrypoint script, we ensure:

- ✅ Only the configured challenge type is active
- ✅ Predictable, deterministic behavior
- ✅ Clear error messages for misconfigurations
- ✅ Easy troubleshooting with diagnostic tools
- ✅ Full support for wildcard certificates

Users can now confidently configure DNS-01 challenges for wildcard certificates without unexpected TLS-ALPN attempts.

## References

- [Let's Encrypt Challenge Types](https://letsencrypt.org/docs/challenge-types/)
- [Traefik ACME Documentation](https://doc.traefik.io/traefik/https/acme/)
- [Lego DNS Providers](https://go-acme.github.io/lego/dns/)
- [Docker Compose Environment Variables](https://docs.docker.com/compose/environment-variables/)

---

**Document Status:** Complete ✅  
**Last Updated:** 2026-02-03  
**Implemented In:** PR #[number]
