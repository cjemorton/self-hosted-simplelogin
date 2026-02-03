# Pull Request: Reimplement Traefik ACME Resolver Logic

## Problem Statement

The previous implementation had both DNS-01 and TLS-ALPN-01 ACME resolvers configured simultaneously in Traefik, which could lead to:
- Configuration conflicts
- Certificate issuance failures
- Unclear which resolver would be used
- Complexity in troubleshooting

The goal was to reimplement the conditional ACME resolver logic entirely as host-side configuration without modifying the Traefik container image.

## Solution

This PR implements a smart entrypoint script that conditionally configures Traefik with ONLY ONE challenge type based on environment variables.

### Architecture

```
┌─────────────────────────────────────────┐
│  Environment Variables (.env)            │
│  - LE_CHALLENGE (tls|dns)               │
│  - LE_DNS_PROVIDER                      │
│  - LE_EMAIL                             │
└──────────────┬──────────────────────────┘
               │
               v
┌─────────────────────────────────────────┐
│  scripts/traefik-entrypoint.sh          │
│  - Reads env vars                       │
│  - Validates configuration              │
│  - Builds CLI args conditionally        │
│  - Ensures mutual exclusivity           │
└──────────────┬──────────────────────────┘
               │
               v
┌─────────────────────────────────────────┐
│  Traefik with SINGLE resolver           │
│  - EITHER dns resolver                  │
│  - OR tls resolver                      │
│  - NEVER both                           │
└─────────────────────────────────────────┘
```

### Key Features

1. **Mutual Exclusivity** - Only one resolver type is ever configured
2. **Validation** - Fails fast with clear errors for invalid configurations
3. **No Image Modifications** - Uses official Traefik image
4. **Testable** - Includes DRY_RUN mode for testing
5. **Well Documented** - Inline comments and comprehensive guide

### Files Changed

#### 1. `scripts/traefik-entrypoint.sh`
- Added `DRY_RUN` mode for testing (lines 12-13, 74-78)
- Conditional resolver configuration logic (lines 32-67)
- Validation for DNS provider requirement (lines 36-42)

**TLS-ALPN Mode:**
```bash
--certificatesresolvers.tls.acme.storage=/etc/traefik/acme/acme-tls.json
--certificatesresolvers.tls.acme.email=${LE_EMAIL}
--certificatesresolvers.tls.acme.tlschallenge=true
```

**DNS-01 Mode:**
```bash
--certificatesresolvers.dns.acme.storage=/etc/traefik/acme/acme-dns.json
--certificatesresolvers.dns.acme.email=${LE_EMAIL}
--certificatesresolvers.dns.acme.dnschallenge=true
--certificatesresolvers.dns.acme.dnschallenge.provider=${LE_DNS_PROVIDER}
```

#### 2. `scripts/test-traefik-entrypoint.sh`
Completely rewritten with 33 comprehensive tests:
- Default TLS-ALPN mode (4 tests)
- Explicit TLS mode (3 tests)
- DNS mode without provider - error case (2 tests)
- DNS mode with provider (5 tests)
- Mutual exclusivity - TLS mode (3 tests)
- Mutual exclusivity - DNS mode (3 tests)
- Common configuration (5 tests)
- Certificate resolver consistency (2 tests)
- Multiple DNS providers (4 tests)
- Email configuration fallback (2 tests)

#### 3. `traefik-compose.yaml`
Already configured correctly:
- ✅ Mounts `./scripts:/scripts:ro` (read-only)
- ✅ Sets `entrypoint: ["/scripts/traefik-entrypoint.sh"]`
- ✅ Includes comprehensive inline documentation

#### 4. `TRAEFIK_RESOLVER_IMPLEMENTATION.md` (New)
Complete implementation guide covering:
- Solution architecture
- Usage examples for both challenge types
- Validation procedures
- Error handling
- Troubleshooting guide
- Supported DNS providers

#### 5. `.env.example`
Already documented with:
- ✅ LE_CHALLENGE explanation (lines 153-176)
- ✅ LE_DNS_PROVIDER configuration (lines 178-192)
- ✅ DNS provider credentials (lines 194-226)

## Test Results

```bash
$ bash scripts/test-traefik-entrypoint.sh
======================================
Testing Traefik Entrypoint Script
======================================

[... 33 tests ...]

======================================
Test Summary
======================================
Total tests: 33
Passed: 33
Failed: 0

✅ All tests passed!

The traefik-entrypoint.sh script correctly:
  ✓ Configures only ONE resolver (DNS or TLS) at a time
  ✓ Fails when DNS mode lacks LE_DNS_PROVIDER
  ✓ Uses different storage files for each resolver
  ✓ Maintains common Traefik configuration
  ✓ Properly sets the certresolver name
```

## Acceptance Criteria

All acceptance criteria from the problem statement are met:

- ✅ **Conditional resolver logic** - Script uses env vars to set up EITHER DNS-01 OR TLS-ALPN-01, never both
- ✅ **Clear error handling** - Fails with detailed error if DNS requested without LE_DNS_PROVIDER
- ✅ **Single challenge type** - CLI arguments arranged so only one challenge type is active
- ✅ **Compose configuration** - Script mounted as `/scripts/traefik-entrypoint.sh` (read-only) with entrypoint set
- ✅ **Documentation** - README/compose comments explain the approach
- ✅ **Test coverage** - Test script verifies mutual exclusivity and correct CLI output
- ✅ **No image modifications** - Solution uses official Traefik image with host-side logic only

## Usage Examples

### TLS-ALPN Challenge (Default)

```bash
# .env
LE_CHALLENGE=tls
LE_EMAIL=admin@example.com

# Start Traefik
docker compose -f traefik-compose.yaml up -d

# Verify
docker logs traefik | grep "INFO: Configuring"
# Output: INFO: Configuring Traefik for TLS-ALPN-01 ACME challenge
```

### DNS-01 Challenge (Wildcard Certificates)

```bash
# .env
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare
CF_DNS_API_TOKEN=your-token-here
LE_EMAIL=admin@example.com

# Start Traefik
docker compose -f traefik-compose.yaml up -d

# Verify
docker logs traefik | grep "INFO: Configuring"
# Output: INFO: Configuring Traefik for DNS-01 ACME challenge
# Output: INFO: DNS Provider: cloudflare
```

## Verification

### Runtime Verification

```bash
# Check which resolver is configured
docker logs traefik | grep certificatesresolvers

# TLS mode shows:
#   --certificatesresolvers.tls.acme.tlschallenge=true
#   (no certificatesresolvers.dns)

# DNS mode shows:
#   --certificatesresolvers.dns.acme.dnschallenge=true
#   (no certificatesresolvers.tls)
```

### Test Execution

```bash
# Run comprehensive test suite
bash scripts/test-traefik-entrypoint.sh

# Expected: All 33 tests pass
```

## Error Handling Example

```bash
# Attempt DNS mode without provider
LE_CHALLENGE=dns docker compose -f traefik-compose.yaml up

# Output:
# INFO: Configuring Traefik for DNS-01 ACME challenge
# INFO: DNS Provider: not-set
# ERROR: LE_CHALLENGE=dns but LE_DNS_PROVIDER is not set!
# ERROR: Please set LE_DNS_PROVIDER in your .env file
# ERROR: See: https://go-acme.github.io/lego/dns/
# Container exits with code 1
```

## Design Decisions

1. **Separate Storage Files** - Each resolver uses its own storage file to prevent conflicts:
   - TLS: `/etc/traefik/acme/acme-tls.json`
   - DNS: `/etc/traefik/acme/acme-dns.json`

2. **Matching Resolver Names** - The certresolver name matches the challenge type:
   - TLS mode: `certresolver=tls`
   - DNS mode: `certresolver=dns`

3. **DRY_RUN Mode** - Allows testing the script logic without Docker:
   ```bash
   DRY_RUN=true LE_CHALLENGE=tls bash scripts/traefik-entrypoint.sh
   ```

4. **Fail Fast** - Script exits immediately on configuration errors rather than allowing silent misconfiguration.

## Benefits

1. **Prevents Configuration Conflicts** - Only one resolver is ever active
2. **Clear Runtime Behavior** - Logs show exactly which resolver is configured
3. **Easier Troubleshooting** - No ambiguity about which challenge type is being used
4. **Maintainable** - No custom Docker image to build/maintain
5. **Testable** - Comprehensive test suite validates behavior
6. **Well Documented** - Users understand how to configure and use the system

## Security Considerations

- Scripts mounted as read-only (`:ro`)
- DNS provider credentials passed via environment variables
- No secrets in code or scripts
- Validation prevents misconfiguration

## References

- [TRAEFIK_RESOLVER_IMPLEMENTATION.md](TRAEFIK_RESOLVER_IMPLEMENTATION.md) - Detailed implementation guide
- [TRAEFIK_ACME_TROUBLESHOOTING.md](TRAEFIK_ACME_TROUBLESHOOTING.md) - Troubleshooting guide
- [Let's Encrypt Challenge Types](https://letsencrypt.org/docs/challenge-types/)
- [Traefik ACME Configuration](https://doc.traefik.io/traefik/https/acme/)
- [Lego DNS Providers](https://go-acme.github.io/lego/dns/)
