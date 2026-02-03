# MTA-STS Auto-Detection Feature Demo

## Example 1: Auto-Detection Mode (No External File)

```bash
$ export DOMAIN=example.com
$ export MTA_STS_MODE=auto
$ bash scripts/detect-mta-sts.sh
```

**Output:**
```
[MTA-STS] Auto-detecting MTA-STS configuration for domain: example.com
[MTA-STS] Checking for external MTA-STS at: https://mta-sts.example.com/.well-known/mta-sts.txt
[MTA-STS] No external MTA-STS file found or not accessible
[MTA-STS] Using internal MTA-STS hosting via Traefik
```

## Example 2: Manual Internal Mode

```bash
$ export DOMAIN=example.com
$ export MTA_STS_MODE=internal
$ bash scripts/detect-mta-sts.sh
```

**Output:**
```
[MTA-STS] MTA-STS mode set to 'internal' (manual override, skipping auto-detection)
[MTA-STS] Using internal MTA-STS hosting via Traefik
```

## Example 3: Manual External Mode

```bash
$ export DOMAIN=example.com
$ export MTA_STS_MODE=external
$ bash scripts/detect-mta-sts.sh
```

**Output:**
```
[MTA-STS] MTA-STS mode set to 'external' (manual override, skipping auto-detection)
[MTA-STS] Using external MTA-STS hosting (internal hosting disabled)
```

## Example 4: Export Mode for Environment Variables

```bash
$ export DOMAIN=example.com
$ export MTA_STS_MODE=external
$ bash scripts/detect-mta-sts.sh --export
```

**Output:**
```
export MTA_STS_INTERNAL_ENABLED=false
export MTA_STS_EXTERNAL_DETECTED=true
export MTA_STS_STATUS=external
```

## Example 5: Startup Script

```bash
$ cat > .env << 'ENVEOF'
DOMAIN=example.com
SUBDOMAIN=app
POSTGRES_USER=myuser
POSTGRES_PASSWORD=mypassword
FLASK_SECRET=mysecret
MTA_STS_MODE=auto
MTA_STS_POLICY_MODE=testing
MTA_STS_MAX_AGE=86400
ENVEOF

$ ./startup.sh
```

**Output:**
```
=========================================
  SimpleLogin Startup
=========================================

[INFO] Detecting MTA-STS configuration...
[MTA-STS] Auto-detecting MTA-STS configuration for domain: example.com
[MTA-STS] Checking for external MTA-STS at: https://mta-sts.example.com/.well-known/mta-sts.txt
[MTA-STS] No external MTA-STS file found or not accessible
[MTA-STS] Using internal MTA-STS hosting via Traefik

[INFO] MTA-STS: Using internal hosting via Traefik
[INFO] Ensure mta-sts.example.com DNS points to this server
[INFO] Starting Docker Compose stack...

[PASS] SimpleLogin stack started successfully!

=========================================
  MTA-STS Configuration Summary
=========================================

Mode: auto
Status: internal
Internal Hosting: true
External Detected: false

[INFO] View logs with: docker compose logs -f
[INFO] Stop services with: docker compose down
```

## Example 6: Container Startup Logs

```bash
$ docker compose logs sl-app | grep MTA-STS
```

**Output:**
```
sl-app  | [INFO] Detecting MTA-STS configuration...
sl-app  | [MTA-STS] Auto-detecting MTA-STS configuration for domain: example.com
sl-app  | [MTA-STS] Checking for external MTA-STS at: https://mta-sts.example.com/.well-known/mta-sts.txt
sl-app  | [MTA-STS] No external MTA-STS file found or not accessible
sl-app  | [MTA-STS] Using internal MTA-STS hosting via Traefik
```

## Example 7: Preflight Check

```bash
$ bash scripts/preflight-check.sh
```

**Output (MTA-STS section):**
```
[INFO] Checking MTA-STS configuration...
[PASS] MTA_STS_MODE is set to: auto
[INFO] Running MTA-STS auto-detection...
[INFO] External MTA-STS not found, will use internal hosting
[INFO] MTA-STS requires the following DNS records:
[INFO]   1. A record: mta-sts.example.com -> your server IP
[INFO]   2. TXT record: _mta-sts.example.com -> v=STSv1; id=<timestamp>
[INFO] See README.md for detailed DNS configuration
```

## Example 8: Test Suite Execution

```bash
$ bash scripts/test-mta-sts-detection.sh
```

**Output:**
```
=========================================
  MTA-STS Detection Test Suite
=========================================

[TEST] Checking if detect-mta-sts.sh exists and is executable...
[PASS] detect-mta-sts.sh exists and is executable
[TEST] Testing that script requires DOMAIN...
[PASS] Script correctly requires DOMAIN
[TEST] Testing internal mode...
[PASS] Internal mode works correctly
[TEST] Testing external mode...
[PASS] External mode works correctly
[TEST] Testing disabled mode...
[PASS] Disabled mode works correctly
[TEST] Testing invalid mode handling...
[PASS] Invalid mode correctly rejected
[TEST] Testing auto mode with no external MTA-STS...
[PASS] Auto mode defaults to internal when no external found
[TEST] Testing environment variables in compose file...
[PASS] Compose file uses MTA-STS environment variables
[TEST] Testing .env.example has MTA-STS variables...
[PASS] .env.example includes MTA-STS configuration
[TEST] Testing preflight check includes MTA-STS validation...
[PASS] Preflight check includes MTA-STS validation
[TEST] Testing README includes MTA-STS documentation...
[PASS] README includes MTA-STS auto-detection documentation

=========================================
  Test Summary
=========================================

Passed: 11
Failed: 0

✓ All tests passed!
```

## Example 9: Testing External MTA-STS File

```bash
$ curl https://mta-sts.example.com/.well-known/mta-sts.txt
```

**Expected Output (Internal Hosting):**
```
version: STSv1
mode: testing
mx: app.example.com
max_age: 86400
```

## Example 10: Validation of External File

If external MTA-STS is detected:

```bash
$ export DOMAIN=yourdomain.com
$ export MTA_STS_MODE=auto
$ bash scripts/detect-mta-sts.sh
```

**Output (Valid External File Found):**
```
[MTA-STS] Auto-detecting MTA-STS configuration for domain: yourdomain.com
[MTA-STS] Checking for external MTA-STS at: https://mta-sts.yourdomain.com/.well-known/mta-sts.txt
[MTA-STS] External MTA-STS file found, validating content...
[MTA-STS] Valid external MTA-STS file detected!
[MTA-STS] External MTA-STS configuration:
  version: STSv1
  mode: enforce
  mx: app.yourdomain.com
  max_age: 604800
[MTA-STS] Disabling internal MTA-STS hosting (using external configuration)
```

**Output (Invalid External File):**
```
[MTA-STS] Auto-detecting MTA-STS configuration for domain: yourdomain.com
[MTA-STS] Checking for external MTA-STS at: https://mta-sts.yourdomain.com/.well-known/mta-sts.txt
[MTA-STS] External MTA-STS file found, validating content...
[MTA-STS] External MTA-STS missing 'version: STSv1' field
[MTA-STS] External MTA-STS file is invalid or incomplete
[MTA-STS] Using internal MTA-STS hosting via Traefik
```

## Configuration Files

### .env File Example

```bash
# Domain configuration
DOMAIN=example.com
SUBDOMAIN=app

# MTA-STS Configuration
MTA_STS_MODE=auto                    # auto, internal, external, or disabled
MTA_STS_POLICY_MODE=testing          # testing, enforce, or none
MTA_STS_MAX_AGE=86400                # 24 hours in seconds

# Other required settings
POSTGRES_USER=myuser
POSTGRES_PASSWORD=mypassword
FLASK_SECRET=mysecret
```

### External MTA-STS File Example (for Cloudflare Pages/GitHub Pages)

File: `.well-known/mta-sts.txt`

```
version: STSv1
mode: testing
mx: app.example.com
max_age: 86400
```

## DNS Configuration

### Required DNS Records

1. **A Record for MTA-STS subdomain:**
   ```
   mta-sts.example.com.    3600    IN    A    <your-server-IP>
   ```
   Or for external hosting:
   ```
   mta-sts.example.com.    3600    IN    A    <cloudflare-IP>
   ```

2. **TXT Record for MTA-STS policy:**
   ```
   _mta-sts.example.com.   3600    IN    TXT   "v=STSv1; id=1234567890"
   ```

### Verify DNS Records

```bash
# Check A record
$ dig @1.1.1.1 mta-sts.example.com A

# Check TXT record
$ dig @1.1.1.1 _mta-sts.example.com TXT
```

## Troubleshooting Commands

### Check Detection Status
```bash
$ docker compose logs sl-app | grep MTA-STS
```

### Test External Accessibility
```bash
$ curl -v https://mta-sts.example.com/.well-known/mta-sts.txt
```

### Run Detection Manually
```bash
$ docker compose exec sl-app bash scripts/detect-mta-sts.sh
```

### Check Configuration Variables
```bash
$ docker compose exec sl-app env | grep MTA_STS
```

### Test with Different Modes
```bash
# Test auto mode
$ DOMAIN=example.com MTA_STS_MODE=auto bash scripts/detect-mta-sts.sh

# Test internal mode
$ DOMAIN=example.com MTA_STS_MODE=internal bash scripts/detect-mta-sts.sh

# Test external mode
$ DOMAIN=example.com MTA_STS_MODE=external bash scripts/detect-mta-sts.sh

# Test disabled mode
$ DOMAIN=example.com MTA_STS_MODE=disabled bash scripts/detect-mta-sts.sh
```

## Summary

The MTA-STS auto-detection feature provides:

✅ **Transparent auto-detection** - Automatically finds external MTA-STS hosting
✅ **Safe fallback** - Uses internal hosting if external not found
✅ **Clear logging** - All steps logged with detailed information
✅ **Flexible configuration** - Four modes to suit any deployment
✅ **Comprehensive validation** - External files validated against RFC 8461
✅ **Easy troubleshooting** - Clear error messages and debug commands

Start using it today with just three steps:
1. Add MTA-STS configuration to `.env`
2. Run `./startup.sh` or `./up.sh`
3. Verify with `docker compose logs sl-app | grep MTA-STS`
