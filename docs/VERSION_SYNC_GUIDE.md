# Version Synchronization Guide

This guide explains the new version synchronization features added to `up.sh` that automate the process of updating to the latest SimpleLogin version.

## Table of Contents

- [Overview](#overview)
- [New Features](#new-features)
- [Usage Examples](#usage-examples)
- [Configuration](#configuration)
- [Error Handling](#error-handling)
- [Troubleshooting](#troubleshooting)

## Overview

The `up.sh` script now includes automated version synchronization capabilities that:
- Fetch the latest SimpleLogin release from GitHub
- Validate Docker image availability
- Retry with configurable delays if images aren't ready yet
- Fall back to last available version if needed
- Update your `.env` configuration automatically
- Pull the Docker images

## New Features

### 1. Automatic Version Updates (`--update-latest`)

Automatically fetch and update to the latest SimpleLogin version:

```bash
./up.sh --update-latest
```

This will:
1. Query GitHub API for the latest SimpleLogin release tag
2. Check if the corresponding Docker image exists in your configured repository
3. Retry with delays if the image isn't available yet (useful for new releases)
4. Fall back to the last available Docker tag if retries are exhausted
5. Update `SL_VERSION` in your `.env` file
6. Pull the Docker image
7. Start the containers

### 2. Docker Login Check

By default, `up.sh` now verifies you're logged in to Docker before operations. This prevents failures when pulling private images.

To skip this check (not recommended):
```bash
./up.sh --no-docker-login-check
```

### 3. Configurable Retry Logic

When checking for Docker image availability, you can customize:

**Retry Delay** (default: 15 seconds):
```bash
./up.sh --update-latest --retry-delay 30
```

**Max Retries** (default: 20):
```bash
./up.sh --update-latest --max-retries 10
```

**Combined:**
```bash
./up.sh --update-latest --retry-delay 5 --max-retries 40
# Total wait time: 5s × 40 = 200 seconds (3.3 minutes)
```

## Usage Examples

### Basic Version Update

```bash
# Update to latest version with default settings
./up.sh --update-latest
```

### Update with Custom Retry Settings

```bash
# Wait up to 10 minutes (30s × 20 retries)
./up.sh --update-latest --retry-delay 30 --max-retries 20
```

### Update and Start in Foreground

```bash
# Update and watch the logs
./up.sh --update-latest -f
```

### Fresh Install with Latest Version

```bash
# Wipe data, update, and start fresh
./up.sh --update-latest -r -y
```

### Update Without Docker Login Check

```bash
# Skip login verification (not recommended for production)
./up.sh --update-latest --no-docker-login-check
```

### Cleanup and Update

```bash
# Clean up old images, then update
./up.sh --update-latest -c
```

## Configuration

The version synchronization uses environment variables from your `.env` file:

### Required Variables

```env
SL_VERSION=v2026.02.02-staging-test-02  # Will be auto-updated
```

### Optional Variables

```env
SL_DOCKER_REPO=clem16               # Docker repository (default: clem16)
SL_IMAGE=simplelogin-app            # Image name (default: simplelogin-app)
```

### Override with Custom Image

If you want complete control, you can override with a custom image:

```env
SL_CUSTOM_IMAGE=myregistry/myimage:mytag
```

When `SL_CUSTOM_IMAGE` is set, the auto-update feature will not modify it.

## Error Handling

The script handles various error scenarios gracefully:

### Network Issues

If GitHub API is unreachable:
```
ERROR: Failed to fetch latest release from GitHub API
[INFO] Trying to fetch latest tag instead...
```

If that also fails:
```
ERROR: Failed to fetch tags from GitHub API
```

### Docker Registry Issues

If the Docker image doesn't exist:
```
⚠️  WARNING: Docker image not available after 20 retries: clem16/simplelogin-app:v4.78.4
Attempting fallback to last available Docker tag...
```

### File Permission Issues

If `.env` cannot be updated:
```
ERROR: Failed to update .env file
```

The script creates a backup (`.env.backup`) before any changes.

### Invalid Parameters

If you provide invalid values:
```bash
$ ./up.sh --retry-delay abc
ERROR: --retry-delay must be a positive number

$ ./up.sh --max-retries xyz
ERROR: --max-retries must be a positive number
```

## Troubleshooting

### Problem: Docker login check fails

**Symptoms:**
```
ERROR: Docker is not logged in!
Please log in to Docker before running this script:
  docker login
```

**Solution:**
```bash
# Log in to Docker Hub
docker login

# Or skip the check (not recommended)
./up.sh --no-docker-login-check
```

### Problem: Image not found after retries

**Symptoms:**
```
⚠️  WARNING: Docker image not available after 20 retries
Attempting fallback to last available Docker tag...
```

**Possible Causes:**
1. New release was just published, images are still building
2. Your Docker repository doesn't have the version yet
3. Network connectivity issues

**Solutions:**
1. Wait longer and try again
2. Increase retry settings:
   ```bash
   ./up.sh --update-latest --retry-delay 30 --max-retries 40
   ```
3. Check your Docker repository has the images
4. Manually set a known version in `.env`

### Problem: GitHub API rate limit

**Symptoms:**
```
ERROR: Failed to fetch latest release from GitHub API
```

**Solution:**
GitHub API has rate limits. If you hit them:
1. Wait an hour for the limit to reset
2. Authenticate with a GitHub token (future enhancement)
3. Manually check GitHub and update `.env`:
   ```bash
   # Edit .env
   SL_VERSION=v4.78.4
   
   # Then start normally
   ./up.sh
   ```

### Problem: Version update succeeded but image won't pull

**Symptoms:**
```
✓ Version update completed successfully!
[INFO] Pulling Docker image: clem16/simplelogin-app:v4.78.4
ERROR: Failed to pull Docker image
```

**Solution:**
1. Check Docker login status
2. Verify image exists in registry
3. Check network connectivity
4. Manually pull:
   ```bash
   docker pull clem16/simplelogin-app:v4.78.4
   ```

### Problem: Want to rollback to previous version

**Solution:**
If auto-update caused issues, your previous `.env` is backed up:

```bash
# Restore the backup
cp .env.backup .env

# Or manually edit .env
vim .env
# Change SL_VERSION to desired version

# Restart containers
./up.sh
```

## Advanced Usage

### Automation with CI/CD

For automated deployments:

```bash
#!/bin/bash
# update-production.sh

# Update to latest, no prompts, skip login check (assuming already logged in)
./up.sh --update-latest --no-docker-login-check -y

# Or with specific retry settings for CI environment
./up.sh --update-latest \
  --retry-delay 10 \
  --max-retries 30 \
  --no-docker-login-check \
  -y
```

### Monitoring for New Versions

You can check for new versions without updating:

```bash
# Get current version
CURRENT=$(grep '^SL_VERSION=' .env | cut -d'=' -f2)

# Get latest from GitHub
LATEST=$(curl -s https://api.github.com/repos/simple-login/app/releases/latest | grep '"tag_name":' | cut -d'"' -f4)

echo "Current: $CURRENT"
echo "Latest: $LATEST"

if [ "$CURRENT" != "$LATEST" ]; then
  echo "Update available!"
fi
```

### Testing Before Production

Always test version updates in a staging environment:

```bash
# On staging server
./up.sh --update-latest -f  # Watch logs in foreground

# If successful, deploy to production
ssh production "./up.sh --update-latest"
```

## Related Documentation

- [Main README](../README.md) - Setup and installation
- [TROUBLESHOOTING](TROUBLESHOOTING.md) - General troubleshooting guide
- [up.sh help](up.sh) - Run `./up.sh --help` for quick reference

## Support

If you encounter issues not covered here:
1. Check the main [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review the script logs carefully
3. Open an issue on GitHub with:
   - Error messages
   - Your `.env` configuration (redact sensitive data)
   - Docker version
   - Operating system
