# Traefik ACME Resolver Implementation

## Overview

This implementation provides conditional ACME resolver logic for Traefik entirely as host-side configuration—no custom container image required. The solution ensures that only ONE challenge type (DNS-01 or TLS-ALPN-01) is configured at any given time, preventing conflicts and configuration errors.

## Solution Architecture

### 1. Host-Side Entrypoint Script (`scripts/traefik-entrypoint.sh`)

The entrypoint script is the core of this implementation. It:

- **Reads environment variables** at container start time
- **Conditionally builds Traefik CLI arguments** based on `LE_CHALLENGE`
- **Ensures mutual exclusivity** between DNS and TLS-ALPN resolvers
- **Validates configuration** before starting Traefik
- **Delegates to the original Traefik entrypoint** with the constructed arguments

#### Key Features:

```bash
# Environment Variables Used:
LE_CHALLENGE=tls|dns       # Challenge type selection
LE_DNS_PROVIDER=<provider> # Required when LE_CHALLENGE=dns
LE_EMAIL=<email>           # Let's Encrypt email
```

#### Mutual Exclusivity Logic:

```bash
if [ "$LE_CHALLENGE" = "dns" ]; then
    # Configure ONLY DNS resolver
    --certificatesresolvers.dns.acme.dnschallenge=true
    --certificatesresolvers.dns.acme.dnschallenge.provider=${LE_DNS_PROVIDER}
else
    # Configure ONLY TLS resolver
    --certificatesresolvers.tls.acme.tlschallenge=true
fi
```

### 2. Docker Compose Configuration (`traefik-compose.yaml`)

The Traefik service is configured to:

- **Use the custom entrypoint**: `entrypoint: ["/scripts/traefik-entrypoint.sh"]`
- **Mount the scripts directory**: `- ./scripts:/scripts:ro` (read-only)
- **Pass environment variables**: `env_file: ${SL_CONFIG_PATH:-.env}`

### 3. Comprehensive Testing (`scripts/test-traefik-entrypoint.sh`)

A test script validates:

- ✅ TLS-ALPN mode works (default and explicit)
- ✅ DNS mode works with provider
- ✅ DNS mode fails without provider (with clear error)
- ✅ **Mutual exclusivity** - DNS mode doesn't include TLS resolver
- ✅ **Mutual exclusivity** - TLS mode doesn't include DNS resolver
- ✅ Common configuration is present in both modes
- ✅ Different DNS providers work correctly
- ✅ Email configuration and fallback behavior

**Test Results:**
```
Total tests: 33
Passed: 33
Failed: 0
```

## Usage

### TLS-ALPN Challenge (Default)

No configuration needed. Just ensure ports 80 and 443 are accessible:

```env
# .env file
LE_CHALLENGE=tls  # or leave unset
LE_EMAIL=admin@example.com
```

Start Traefik:
```bash
docker compose -f traefik-compose.yaml up -d
```

### DNS-01 Challenge (Wildcard Certificates)

Configure your DNS provider:

```env
# .env file
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare
CF_DNS_API_TOKEN=your-cloudflare-api-token-here
LE_EMAIL=admin@example.com
```

Start Traefik:
```bash
docker compose -f traefik-compose.yaml up -d
```

## Validation

### Verify Configuration at Runtime

Check which resolver is active:
```bash
docker logs traefik | grep "INFO: Configuring"
```

Expected output for TLS mode:
```
INFO: Configuring Traefik for TLS-ALPN-01 ACME challenge
INFO: Certificate resolver 'tls' will be used
```

Expected output for DNS mode:
```
INFO: Configuring Traefik for DNS-01 ACME challenge
INFO: DNS Provider: cloudflare
INFO: Certificate resolver 'dns' will be used
```

### Run Tests

```bash
bash scripts/test-traefik-entrypoint.sh
```

### Verify Mutual Exclusivity

Inspect the running Traefik configuration:
```bash
# For TLS mode, should NOT see DNS resolver
docker logs traefik | grep certificatesresolvers

# Should only see: certificatesresolvers.tls.acme.tlschallenge=true
# Should NOT see: certificatesresolvers.dns
```

## Error Handling

### Missing DNS Provider

If `LE_CHALLENGE=dns` but `LE_DNS_PROVIDER` is not set:

```
ERROR: LE_CHALLENGE=dns but LE_DNS_PROVIDER is not set!
ERROR: Please set LE_DNS_PROVIDER in your .env file
ERROR: See: https://go-acme.github.io/lego/dns/
```

The container will exit with code 1, preventing misconfiguration.

## Design Principles

1. **No Custom Image** - Uses official Traefik image with host-side scripting
2. **Mutual Exclusivity** - Only one resolver type is ever configured
3. **Fail Fast** - Clear errors prevent silent misconfigurations
4. **Testable** - DRY_RUN mode allows testing without Docker
5. **Documented** - Inline comments explain the approach
6. **Safe Defaults** - TLS-ALPN works out-of-the-box

## Implementation Details

### Separate Storage Files

Each resolver uses its own storage file to prevent conflicts:

- TLS-ALPN: `/etc/traefik/acme/acme-tls.json`
- DNS-01: `/etc/traefik/acme/acme-dns.json`

### Certificate Resolver Naming

The `certresolver` name matches the challenge type:

- TLS-ALPN mode: `--entrypoints.websecure.http.tls.certresolver=tls`
- DNS mode: `--entrypoints.websecure.http.tls.certresolver=dns`

This makes it clear which resolver is in use and prevents confusion.

## Troubleshooting

### Container Fails to Start

Check logs:
```bash
docker logs traefik
```

Common issues:
- Missing `LE_DNS_PROVIDER` when using DNS mode
- Invalid DNS provider name
- Missing DNS provider credentials

### Certificates Not Issuing

1. Verify the resolver is configured:
   ```bash
   docker logs traefik | grep certificatesresolvers
   ```

2. Check ACME logs:
   ```bash
   docker logs traefik | grep acme
   ```

3. Run diagnostics:
   ```bash
   bash scripts/traefik-diagnostics.sh
   ```

## Supported DNS Providers

See: https://go-acme.github.io/lego/dns/

Common providers include:
- Cloudflare (`cloudflare`)
- AWS Route 53 (`route53`)
- Azure DNS (`azuredns`)
- Google Cloud DNS (`gcloud`)
- DigitalOcean (`digitalocean`)
- And 100+ others

## References

- [Let's Encrypt Challenge Types](https://letsencrypt.org/docs/challenge-types/)
- [Traefik ACME Documentation](https://doc.traefik.io/traefik/https/acme/)
- [Lego DNS Providers](https://go-acme.github.io/lego/dns/)
- [Repository Troubleshooting Guide](TRAEFIK_ACME_TROUBLESHOOTING.md)
