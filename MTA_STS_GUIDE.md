# MTA-STS Auto-Detection Feature

## Overview

This feature enables SimpleLogin to automatically detect and adapt to external MTA-STS hosting (e.g., Cloudflare Pages, GitHub Pages) while maintaining backward compatibility with internal hosting via Traefik.

## Key Features

✅ **Auto-Detection** - Automatically detects external MTA-STS hosting at startup
✅ **Manual Override** - Full control via environment variables
✅ **Flexible Configuration** - Support for internal, external, or disabled modes
✅ **Validation** - Validates external MTA-STS file format and content
✅ **Transparent Logging** - Clear startup logs showing which source is used
✅ **Conflict Prevention** - Warns about potential double-hosting conflicts
✅ **Backward Compatible** - Defaults to internal hosting if no external file found

## Quick Start

### 1. Configuration Options

Add to your `.env` file:

```bash
# MTA-STS hosting mode: auto, internal, external, or disabled
MTA_STS_MODE=auto

# MTA-STS policy mode: testing, enforce, or none
MTA_STS_POLICY_MODE=testing

# MTA-STS max_age in seconds (86400 = 24 hours)
MTA_STS_MAX_AGE=86400
```

### 2. Mode Descriptions

| Mode | Description | Use Case |
|------|-------------|----------|
| `auto` | Auto-detect external hosting, fallback to internal | **Recommended** - Let SimpleLogin decide |
| `internal` | Force internal hosting via Traefik | Traditional self-hosted setup |
| `external` | Disable internal, assume external hosting | Using Cloudflare Pages, GitHub Pages, etc. |
| `disabled` | Completely disable MTA-STS | Testing or non-production environments |

### 3. Startup

Use the new startup script for automatic detection:

```bash
./startup.sh
```

Or use the traditional method (detection still runs in container):

```bash
./up.sh
```

### 4. Verify Configuration

Check startup logs:

```bash
docker compose logs sl-app | grep MTA-STS
```

Expected output:
```
[MTA-STS] Auto-detecting MTA-STS configuration for domain: example.com
[MTA-STS] Checking for external MTA-STS at: https://mta-sts.example.com/.well-known/mta-sts.txt
[MTA-STS] No external MTA-STS file found or not accessible
[MTA-STS] Using internal MTA-STS hosting via Traefik
```

Test your MTA-STS file:

```bash
curl https://mta-sts.yourdomain.com/.well-known/mta-sts.txt
```

## External Hosting Setup

### Option 1: Cloudflare Pages

1. Create a repository with this structure:
   ```
   .well-known/
     mta-sts.txt
   ```

2. Content of `mta-sts.txt`:
   ```
   version: STSv1
   mode: testing
   mx: app.yourdomain.com
   max_age: 86400
   ```

3. Deploy to Cloudflare Pages with custom domain `mta-sts.yourdomain.com`

4. Set in `.env`:
   ```bash
   MTA_STS_MODE=external
   ```

5. Restart SimpleLogin:
   ```bash
   docker compose down
   ./startup.sh
   ```

### Option 2: GitHub Pages

1. Create a repository with `.well-known/mta-sts.txt`
2. Enable GitHub Pages
3. Configure custom domain `mta-sts.yourdomain.com`
4. Follow steps 4-5 from Cloudflare Pages setup

### Option 3: Any Static Host

- Host the file at: `https://mta-sts.yourdomain.com/.well-known/mta-sts.txt`
- Ensure it's publicly accessible via HTTPS
- Set `MTA_STS_MODE=external` in `.env`

## DNS Configuration

Required DNS records for MTA-STS:

1. **A Record** for `mta-sts.yourdomain.com`:
   - Internal hosting: Point to your server IP
   - External hosting: Point to your CDN/static host IP

2. **TXT Record** for `_mta-sts.yourdomain.com`:
   ```
   v=STSv1; id=1234567890
   ```
   Update the `id` timestamp whenever you change your MTA-STS policy.

Generate TXT record:
```bash
echo "v=STSv1; id=$(date +%s)"
```

## Validation & Testing

### Run Test Suites

Unit tests:
```bash
./scripts/test-mta-sts-detection.sh
```

Integration tests:
```bash
./scripts/test-mta-sts-integration.sh
```

### Pre-flight Check

Run before starting the stack:
```bash
./scripts/preflight-check.sh
```

### Manual Testing

Test auto-detection:
```bash
DOMAIN=yourdomain.com bash scripts/detect-mta-sts.sh
```

Test with specific mode:
```bash
DOMAIN=yourdomain.com MTA_STS_MODE=external bash scripts/detect-mta-sts.sh
```

Get export variables:
```bash
DOMAIN=yourdomain.com bash scripts/detect-mta-sts.sh --export
```

## Troubleshooting

### Issue: Double hosting conflict

**Symptom**: Both internal and external MTA-STS files are accessible

**Important Understanding**: The internal Traefik route configuration (Docker Compose labels) cannot be conditionally removed at runtime. When using external hosting, the labels remain in the configuration but will not cause issues because:
- DNS routing determines which host receives requests
- If `mta-sts.yourdomain.com` DNS points to your external CDN, the internal route never receives traffic
- The internal route only serves requests when DNS points to your SimpleLogin server

**Solution**: 
```bash
# 1. Set external mode
MTA_STS_MODE=external

# 2. Ensure DNS points to external host
# A record: mta-sts.yourdomain.com -> <CDN IP address>
# NOT -> <SimpleLogin server IP>

# 3. Verify DNS
dig mta-sts.yourdomain.com

# 4. Test which endpoint is actually being served
curl https://mta-sts.yourdomain.com/.well-known/mta-sts.txt
```

**For testing internal route while external is configured:**
```bash
# Add to /etc/hosts temporarily
echo "<SimpleLogin-IP> mta-sts.yourdomain.com" >> /etc/hosts
curl https://mta-sts.yourdomain.com/.well-known/mta-sts.txt
# Remove the hosts entry when done
```

### Issue: External file not detected

**Symptom**: Auto-detection falls back to internal despite external file existing

**Causes**:
- External file is not accessible via HTTPS
- External file has invalid format
- DNS not configured correctly
- curl not available in container

**Debug**:
```bash
# Test external accessibility
curl -v https://mta-sts.yourdomain.com/.well-known/mta-sts.txt

# Check detection logs
docker compose logs sl-app | grep MTA-STS

# Run detection manually
docker compose exec sl-app bash scripts/detect-mta-sts.sh
```

### Issue: Invalid external MTA-STS file

**Symptom**: Detection finds file but rejects it as invalid

**Solution**: Ensure file contains all required fields:
- `version: STSv1`
- `mode: testing` or `enforce`
- `mx: yourmailserver.com`
- `max_age: 86400`

### Issue: MX mismatch warning

**Symptom**: Warning about MX server mismatch

**Solution**: Update external MTA-STS file to match:
```
mx: app.yourdomain.com
```

Or update `SUBDOMAIN` in `.env` to match external configuration.

## File Reference

### New Files

- `scripts/detect-mta-sts.sh` - MTA-STS detection script
- `scripts/test-mta-sts-detection.sh` - Unit test suite
- `scripts/test-mta-sts-integration.sh` - Integration test suite
- `startup.sh` - Enhanced startup script with detection
- `MTA_STS_GUIDE.md` - This guide

### Modified Files

- `.env.example` - Added MTA-STS configuration variables
- `simple-login-compose.yaml` - Made MTA-STS configurable via env vars
- `scripts/resource-optimized-entrypoint.sh` - Added MTA-STS detection call
- `scripts/preflight-check.sh` - Added MTA-STS validation
- `README.md` - Added comprehensive MTA-STS documentation

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MTA_STS_MODE` | `auto` | Hosting mode: auto, internal, external, disabled |
| `MTA_STS_POLICY_MODE` | `testing` | Policy mode: testing, enforce, none |
| `MTA_STS_MAX_AGE` | `86400` | Cache duration in seconds |
| `MTA_STS_INTERNAL_ENABLED` | (auto) | Detected: true if using internal hosting |
| `MTA_STS_EXTERNAL_DETECTED` | (auto) | Detected: true if external file found |
| `MTA_STS_STATUS` | (auto) | Detected status: internal, external, disabled |

## Architecture

### Detection Flow

```
┌─────────────────────────────────────┐
│   Container Startup (app service)   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  resource-optimized-entrypoint.sh   │
│  Calls: detect-mta-sts.sh           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      MTA_STS_MODE check             │
├─────────────────────────────────────┤
│  auto     → Check external          │
│  internal → Skip detection          │
│  external → Skip detection          │
│  disabled → Skip detection          │
└──────────────┬──────────────────────┘
               │
      ┌────────┴──────────┐
      │                   │
      ▼                   ▼
┌───────────┐      ┌─────────────┐
│ External  │      │  Fallback   │
│  Found    │      │  Internal   │
└─────┬─────┘      └──────┬──────┘
      │                   │
      ▼                   ▼
┌──────────────────────────────┐
│   Export Environment Vars    │
│   - MTA_STS_INTERNAL_ENABLED │
│   - MTA_STS_EXTERNAL_DETECTED│
│   - MTA_STS_STATUS           │
└──────────────┬───────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│    Application Starts Normally      │
│    Traefik uses config from .env    │
└─────────────────────────────────────┘
```

### Detection Logic

1. **Check MTA_STS_MODE**
   - If not `auto`, use manual setting
   - If `auto`, proceed to detection

2. **Fetch External File**
   - URL: `https://mta-sts.${DOMAIN}/.well-known/mta-sts.txt`
   - Timeout: 10 seconds
   - Method: HTTPS GET with curl

3. **Validate Content**
   - Check for required fields: version, mode, mx, max_age
   - Verify format matches RFC 8461
   - Warn if MX doesn't match expected value

4. **Export Configuration**
   - Set environment variables for docker-compose
   - Log detection results
   - Continue with startup

## Best Practices

### Production Setup

1. **Start with testing mode**
   ```bash
   MTA_STS_MODE=auto
   MTA_STS_POLICY_MODE=testing
   MTA_STS_MAX_AGE=86400  # 1 day
   ```

2. **Monitor TLS reports** (configure TLSRPT)
   - Create DNS TXT record: `_smtp._tls.yourdomain.com`
   - Value: `v=TLSRPTv1; rua=mailto:tls-reports@yourdomain.com`

3. **After validation, switch to enforce**
   ```bash
   MTA_STS_POLICY_MODE=enforce
   MTA_STS_MAX_AGE=604800  # 7 days
   ```

4. **For high availability, use external hosting**
   - Reduces load on your server
   - CDN caching for faster delivery
   - Independent of server restarts

### Development/Testing Setup

```bash
MTA_STS_MODE=disabled  # or use testing mode
```

### Migration from Internal to External

1. Set up external hosting
2. Verify external file is accessible
3. Set `MTA_STS_MODE=auto` (will detect automatically)
4. Or set `MTA_STS_MODE=external` (explicit)
5. Restart: `docker compose down && ./startup.sh`
6. Verify logs show external detection

## Support

### Online Validators

- [Hardenize](https://www.hardenize.com/) - Comprehensive email security check
- [MTA-STS Validator](https://aykevl.nl/apps/mta-sts/) - MTA-STS specific validator
- [Google CheckMX](https://toolbox.googleapps.com/apps/checkmx/) - MX and security checks

### Documentation

- [RFC 8461 - SMTP MTA-STS](https://datatracker.ietf.org/doc/html/rfc8461)
- [RFC 8460 - SMTP TLS Reporting](https://datatracker.ietf.org/doc/html/rfc8460)
- [SimpleLogin Documentation](https://github.com/simple-login/app)

## Version History

- **v1.0.0** (2024) - Initial implementation
  - Auto-detection of external MTA-STS hosting
  - Manual mode overrides (auto/internal/external/disabled)
  - Configuration via environment variables
  - Comprehensive test suites
  - Enhanced startup script
  - Updated documentation
