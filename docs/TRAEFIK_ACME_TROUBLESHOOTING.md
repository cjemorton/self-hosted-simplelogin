# Traefik ACME Challenge Troubleshooting Guide

This guide helps you verify and troubleshoot Let's Encrypt certificate issuance with Traefik.

## Table of Contents
- [Quick Verification Commands](#quick-verification-commands)
- [Understanding Challenge Types](#understanding-challenge-types)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Detailed Diagnostics](#detailed-diagnostics)

## Quick Verification Commands

### 1. Check Environment Variables in Traefik Container

Verify that your .env file is properly loaded:

```bash
# Check if LE_CHALLENGE is set correctly
docker exec traefik env | grep LE_CHALLENGE

# Check DNS provider (if using DNS challenge)
docker exec traefik env | grep LE_DNS_PROVIDER

# Check Cloudflare token (if using Cloudflare)
docker exec traefik env | grep CF_DNS_API_TOKEN
```

**Expected output for DNS challenge:**
```
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare
CF_DNS_API_TOKEN=your-token-here
```

### 2. Check Traefik Startup Logs

View the logs to see which ACME challenge was configured:

```bash
docker logs traefik --tail 50
```

**Look for these messages:**
- TLS-ALPN mode: `INFO: Configuring Traefik for TLS-ALPN (HTTP-01) ACME challenge`
- DNS mode: `INFO: Configuring Traefik for DNS-01 ACME challenge`

### 3. Inspect Traefik Configuration

Check which certificate resolvers are active:

```bash
# View the full Traefik command
docker inspect traefik --format='{{.Args}}'

# Or check the process arguments
docker exec traefik ps aux | grep traefik
```

**What to look for:**
- For DNS challenge: Should see `--certificatesresolvers.dns.acme.dnschallenge=true`
- For TLS challenge: Should see `--certificatesresolvers.tls.acme.tlschallenge=true`
- **Important**: You should see ONLY ONE of these, not both!

### 4. Check Router Labels

Verify that routers are using the correct certificate resolver:

```bash
# Check labels on the sl-app container
docker inspect sl-app --format='{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' | grep certresolver
```

**Expected output:**
- For DNS challenge: `traefik.http.routers.sl-app.tls.certresolver=dns`
- For TLS challenge: `traefik.http.routers.sl-app.tls.certresolver=tls`

### 5. Check Active Certificates

View existing certificates:

```bash
# Check TLS challenge certificates
docker exec traefik cat /etc/traefik/acme/acme-tls.json | jq '.tls.Certificates[] | {domain: .domain.main, san: .domain.sans}'

# Check DNS challenge certificates  
docker exec traefik cat /etc/traefik/acme/acme-dns.json | jq '.dns.Certificates[] | {domain: .domain.main, san: .domain.sans}'
```

Note: If `jq` is not available, you can view the raw JSON:
```bash
docker exec traefik cat /etc/traefik/acme/acme-tls.json
docker exec traefik cat /etc/traefik/acme/acme-dns.json
```

## Understanding Challenge Types

### TLS-ALPN Challenge (default: LE_CHALLENGE=tls)

**How it works:**
- Traefik presents a special certificate on port 443 during validation
- Let's Encrypt connects to your server on port 443 to verify ownership
- Requires ports 80 and 443 to be publicly accessible

**Advantages:**
- Works out of the box
- No DNS provider configuration needed
- Fast validation

**Limitations:**
- ❌ Cannot issue wildcard certificates (*.domain.com)
- ❌ Requires ports 80/443 to be open to the internet
- ❌ Cannot work behind certain proxies/CDNs

**Use when:**
- You don't need wildcard certificates
- Your server has direct internet access
- Ports 80 and 443 are open

### DNS-01 Challenge (LE_CHALLENGE=dns)

**How it works:**
- Traefik creates a TXT record in your DNS zone
- Let's Encrypt queries DNS to verify the TXT record
- No direct connection to your server needed

**Advantages:**
- ✅ Can issue wildcard certificates (*.domain.com)
- ✅ Works behind firewalls/proxies
- ✅ No need for public ports

**Limitations:**
- Requires DNS provider API access
- Needs additional configuration (API tokens)
- Slightly slower validation

**Use when:**
- You need wildcard certificates
- Your server is behind a firewall/proxy
- You want to use Cloudflare or similar CDN

## Common Issues and Solutions

### Issue 1: TLS-ALPN Challenge Used Despite LE_CHALLENGE=dns

**Symptoms:**
```bash
docker logs traefik 2>&1 | grep -i "tls-alpn"
# Shows TLS-ALPN challenge attempts
```

**Diagnosis:**
```bash
# Check environment variable
docker exec traefik env | grep LE_CHALLENGE
# If this returns "dns" but TLS-ALPN is still used, there's a config issue
```

**Root Cause:**
- Configuration issue where both resolvers are defined
- .env file not properly loaded
- Hardcoded configuration overriding .env

**Solution:**
1. Ensure you're using the updated traefik-compose.yaml with the entrypoint script
2. Verify .env file has correct settings:
   ```env
   LE_CHALLENGE=dns
   LE_DNS_PROVIDER=cloudflare
   CF_DNS_API_TOKEN=your-token-here
   ```
3. Restart Traefik:
   ```bash
   docker compose restart traefik
   ```

### Issue 2: DNS Provider Not Set

**Symptoms:**
```bash
docker logs traefik 2>&1 | tail -20
# Shows: ERROR: LE_CHALLENGE=dns but LE_DNS_PROVIDER is not set!
```

**Solution:**
Add DNS provider to .env:
```env
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare  # or your provider
```

See [supported providers](https://go-acme.github.io/lego/dns/) for the complete list.

### Issue 3: Invalid or Missing DNS Credentials

**Symptoms:**
```bash
docker logs traefik 2>&1 | grep -i "error"
# Shows DNS authentication failures
```

**Diagnosis:**
```bash
# Check if credentials are set
docker exec traefik env | grep CF_DNS_API_TOKEN
# or for other providers: grep AZURE_CLIENT_ID, etc.
```

**Solution:**

For Cloudflare:
1. Log into Cloudflare Dashboard
2. Go to "My Profile" → "API Tokens"
3. Create token with permissions:
   - Zone - DNS - Edit
   - Zone - Zone - Read
4. Add to .env:
   ```env
   CF_DNS_API_TOKEN=your-token-here
   ```

For other providers, see: https://go-acme.github.io/lego/dns/

### Issue 4: Wrong Certificate Resolver in Router Labels

**Symptoms:**
- DNS challenge configured but certificates not issued
- Logs show "no certificate found" errors

**Diagnosis:**
```bash
docker inspect sl-app --format='{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' | grep certresolver
# Check if certresolver matches LE_CHALLENGE value
```

**Solution:**
The router labels should automatically use `${LE_CHALLENGE}` variable. If they don't:
1. Check simple-login-compose.yaml for hardcoded resolver names
2. Ensure the compose file uses: `tls.certresolver=${LE_CHALLENGE:-tls}`
3. Restart containers:
   ```bash
   docker compose down
   docker compose up -d
   ```

### Issue 5: Port Conflicts or Firewall Issues

**Symptoms (TLS-ALPN only):**
- Certificate validation fails
- Logs show connection timeout or refused

**Diagnosis:**
```bash
# Test if port 443 is accessible from outside
curl -v https://app.yourdomain.com

# Check if port is bound correctly
docker port traefik
# Should show: 443/tcp -> 0.0.0.0:443
```

**Solution:**
1. Ensure ports 80 and 443 are open in firewall
2. Check for conflicts with other services:
   ```bash
   sudo lsof -i :443
   ```
3. If behind a proxy/CDN, consider using DNS challenge instead

### Issue 6: Rate Limits Exceeded

**Symptoms:**
```bash
docker logs traefik 2>&1 | grep -i "rate limit"
```

**Solution:**
1. Let's Encrypt has rate limits (50 certificates per domain per week)
2. Use staging server for testing:
   - Edit `scripts/traefik-entrypoint.sh`
   - Uncomment the caserver line for staging
3. Wait for rate limit to reset (typically 1 week)
4. Once working, switch back to production LE server

## Detailed Diagnostics

### Complete Environment Check

Run this comprehensive check:

```bash
echo "=== Traefik Container Status ==="
docker ps | grep traefik

echo -e "\n=== Environment Variables ==="
echo "LE_CHALLENGE: $(docker exec traefik env | grep LE_CHALLENGE | cut -d= -f2)"
echo "LE_DNS_PROVIDER: $(docker exec traefik env | grep LE_DNS_PROVIDER | cut -d= -f2)"
echo "LE_EMAIL: $(docker exec traefik env | grep LE_EMAIL | cut -d= -f2)"

echo -e "\n=== Traefik Configuration ==="
docker inspect traefik --format='{{.Args}}' | tr ' ' '\n' | grep -E "(certresolver|challenge)"

echo -e "\n=== Router Labels ==="
docker inspect sl-app --format='{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' | grep certresolver

echo -e "\n=== Recent Traefik Logs ==="
docker logs traefik --tail 30

echo -e "\n=== ACME Certificate Status ==="
echo "TLS certificates:"
docker exec traefik ls -lh /etc/traefik/acme/acme-tls.json 2>/dev/null || echo "  No TLS cert file"
echo "DNS certificates:"
docker exec traefik ls -lh /etc/traefik/acme/acme-dns.json 2>/dev/null || echo "  No DNS cert file"
```

### Testing After Changes

After making configuration changes:

1. **Stop containers:**
   ```bash
   docker compose down
   ```

2. **Optionally clear certificates (if testing):**
   ```bash
   docker volume rm traefik-acme
   ```
   ⚠️ **Warning:** This will delete existing certificates!

3. **Start containers:**
   ```bash
   docker compose up -d
   ```

4. **Watch logs:**
   ```bash
   docker logs traefik -f
   ```

5. **Verify:**
   - Check logs for "INFO: DNS-01 challenge configured" or "INFO: TLS-ALPN challenge configured"
   - Wait for certificate issuance (may take 1-2 minutes)
   - Test your domain: `curl -I https://app.yourdomain.com`

### Manual Certificate Request

To force certificate renewal:

```bash
# Delete existing certificates
docker exec traefik rm -f /etc/traefik/acme/acme-*.json

# Restart Traefik
docker compose restart traefik

# Watch for certificate request
docker logs traefik -f
```

## Getting Help

If issues persist after following this guide:

1. **Collect diagnostics:**
   ```bash
   bash scripts/traefik-diagnostics.sh > diagnostics.txt
   ```

2. **Check logs:**
   ```bash
   docker logs traefik > traefik-logs.txt
   docker logs sl-app > sl-app-logs.txt
   ```

3. **Share in GitHub Issues:**
   - Include diagnostics output
   - Include relevant logs (remove sensitive tokens!)
   - Describe your setup (DNS provider, hosting, etc.)

## Additional Resources

- [Let's Encrypt Challenge Types](https://letsencrypt.org/docs/challenge-types/)
- [Traefik ACME Documentation](https://doc.traefik.io/traefik/https/acme/)
- [Lego DNS Providers](https://go-acme.github.io/lego/dns/)
- [Cloudflare API Tokens](https://developers.cloudflare.com/api/tokens/)
