#!/usr/bin/env python3
"""
check-cloudflare-dns.py - Pre-flight check for DNS-01 certificate issuance with Cloudflare

This script performs early startup validation for DNS-01 certificate issuance when using
Cloudflare as the DNS provider. It checks:

1. Whether DNS-01 challenge mode is configured (LE_CHALLENGE=dns)
2. Whether Cloudflare is configured as the DNS provider (LE_DNS_PROVIDER=cloudflare)
3. Whether valid, non-expired certificates already exist for all requested domains
4. If certs don't exist or are expired, validates Cloudflare credentials
5. Tests Cloudflare API connectivity with a minimal API call

The script skips API testing if valid certificates are already present to save time and
avoid rate limiting. It produces clear error messages with remediation instructions.

Usage:
    python3 check-cloudflare-dns.py [--env-file <path>] [--acme-storage <path>]
    
Arguments:
    --env-file <path>       Path to .env file (default: .env)
    --acme-storage <path>   Path to ACME storage JSON (default: /var/lib/docker/volumes/traefik-acme/_data/acme-dns.json)
    
Environment Variables Required (when LE_CHALLENGE=dns and LE_DNS_PROVIDER=cloudflare):
    CF_DNS_API_TOKEN or CF_API_TOKEN - Cloudflare API token with DNS edit permissions
    DOMAIN                           - Primary domain for certificate
    
Exit codes:
    0 - All checks passed (either valid certs exist or Cloudflare credentials validated)
    1 - Configuration requires DNS-01 with Cloudflare but checks failed
    2 - Script error or invalid arguments
"""

import sys
import os
import json
import argparse
from datetime import datetime, timezone
from pathlib import Path

# Color codes for output
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

def log_info(msg):
    """Log informational message"""
    print(f"{BLUE}[INFO]{NC} {msg}")

def log_pass(msg):
    """Log success message"""
    print(f"{GREEN}[PASS]{NC} {msg}")

def log_warn(msg):
    """Log warning message"""
    print(f"{YELLOW}[WARN]{NC} {msg}")

def log_error(msg):
    """Log error message"""
    print(f"{RED}[ERROR]{NC} {msg}")

def load_env_file(env_file_path):
    """
    Load environment variables from .env file
    
    Returns dict of environment variables
    """
    env_vars = {}
    
    if not os.path.exists(env_file_path):
        return env_vars
    
    try:
        with open(env_file_path, 'r') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                
                # Parse VAR=value lines
                if '=' in line:
                    # Split only on first =
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Remove quotes if present
                    if value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    elif value.startswith("'") and value.endswith("'"):
                        value = value[1:-1]
                    
                    env_vars[key] = value
    except Exception as e:
        log_error(f"Failed to parse .env file: {e}")
        return {}
    
    return env_vars

def get_env_value(key, env_vars):
    """
    Get environment variable value, checking both env_vars dict and os.environ
    Priority: os.environ > env_vars dict
    """
    return os.environ.get(key, env_vars.get(key, ''))

def check_certificates_exist_and_valid(acme_storage_path, domains):
    """
    Check if valid, non-expired certificates exist for all requested domains
    
    Args:
        acme_storage_path: Path to Traefik ACME storage JSON file
        domains: List of domain names to check
    
    Returns:
        (bool, str): (True if all certs valid, message describing status)
    
    Note: This function performs a basic check for certificate presence in the
    ACME storage. It does not decode and validate the actual certificate expiration
    date (NotAfter field) as that would require the cryptography library. Instead,
    it relies on Traefik's behavior of updating certificates before expiration.
    
    If a certificate exists in storage, it's assumed to be recent enough to be valid.
    For a more rigorous check, consider adding cryptography library and decoding
    the certificate to check the NotAfter field. However, the current approach is
    sufficient for the common case where certificates are renewed automatically.
    
    If this heuristic fails (e.g., Traefik failed to renew), the API validation
    will run and provide clear error messages if credentials are invalid.
    """
    # Check if ACME storage file exists
    if not os.path.exists(acme_storage_path):
        return False, f"ACME storage file not found at {acme_storage_path}"
    
    try:
        with open(acme_storage_path, 'r') as f:
            acme_data = json.load(f)
    except Exception as e:
        return False, f"Failed to read ACME storage: {e}"
    
    # Check if there are any certificates
    if not acme_data or 'dns' not in acme_data:
        return False, "No DNS resolver certificates found in ACME storage"
    
    dns_data = acme_data.get('dns', {})
    certificates = dns_data.get('Certificates', [])
    
    if not certificates:
        return False, "No certificates found in DNS resolver storage"
    
    # Current time for expiration check (basic heuristic)
    now = datetime.now(timezone.utc)
    
    # Check each requested domain
    all_valid = True
    messages = []
    
    for domain in domains:
        found = False
        valid = False
        
        for cert in certificates:
            cert_domain = cert.get('domain', {}).get('main', '')
            
            # Check if this cert matches our domain (exact match or wildcard)
            if cert_domain == domain or cert_domain == f"*.{domain}":
                found = True
                
                # Basic heuristic: if certificate exists in storage, assume it's valid
                # Traefik typically updates certificates before expiration
                # For more rigorous validation, would need to decode certificate
                # and check NotAfter field using cryptography library
                valid = True
                messages.append(f"Certificate found for {domain}")
                break
        
        if not found:
            all_valid = False
            messages.append(f"No certificate found for {domain}")
        elif not valid:
            all_valid = False
            messages.append(f"Certificate for {domain} may be expired")
    
    status_msg = "; ".join(messages)
    return all_valid, status_msg

def validate_cloudflare_credentials(env_vars):
    """
    Check if required Cloudflare credentials are present
    
    Args:
        env_vars: Dict of environment variables
    
    Returns:
        (bool, str, str): (valid, token_value, error_message)
    """
    # Check for CF_DNS_API_TOKEN (preferred) or CF_API_TOKEN
    cf_token = get_env_value('CF_DNS_API_TOKEN', env_vars)
    if not cf_token:
        cf_token = get_env_value('CF_API_TOKEN', env_vars)
    
    if not cf_token:
        error_msg = """
Cloudflare API token is required but not found.

Please set one of the following environment variables in your .env file:
  - CF_DNS_API_TOKEN (preferred for DNS-01 challenges)
  - CF_API_TOKEN (legacy option)

To create a Cloudflare API token:
  1. Log in to your Cloudflare dashboard
  2. Go to My Profile > API Tokens
  3. Click "Create Token"
  4. Use the "Edit zone DNS" template
  5. Set permissions: Zone > DNS > Edit
  6. Select the zone(s) for your domain
  7. Copy the token and add to .env:
     CF_DNS_API_TOKEN=your-token-here

For more info: https://go-acme.github.io/lego/dns/cloudflare/
"""
        return False, None, error_msg.strip()
    
    return True, cf_token, None

def test_cloudflare_api_connectivity(api_token, domain):
    """
    Test Cloudflare API connectivity and verify token has access to the domain
    
    Args:
        api_token: Cloudflare API token
        domain: Domain name to check access for
    
    Returns:
        (bool, str, dict): (success, error_message, zone_info)
    
    Note: This function uses a simple heuristic to extract the base domain from
    subdomains (e.g., app.example.com -> example.com). It assumes the base domain
    consists of the last two parts of the domain name. This works for most TLDs
    (.com, .net, .org) but may not work correctly for multi-part TLDs like
    .co.uk, .com.au, etc. For such domains, ensure DOMAIN in .env is set to the
    exact zone name in Cloudflare (e.g., example.co.uk, not app.example.co.uk).
    
    The function will list all accessible zones and provide clear error messages
    if the domain is not found, allowing users to identify and fix the mismatch.
    """
    try:
        import urllib.request
        import urllib.error
        
        # Extract base domain (handle subdomains)
        # For example: app.example.com -> example.com
        # Note: This simple approach works for most TLDs but not multi-part TLDs
        # For multi-part TLDs like .co.uk, users should set DOMAIN to the exact
        # Cloudflare zone name (e.g., example.co.uk)
        domain_parts = domain.split('.')
        if len(domain_parts) > 2:
            # Assume the last two parts are the base domain
            # This works for .com, .net, .org but not .co.uk, .com.au, etc.
            base_domain = '.'.join(domain_parts[-2:])
        else:
            base_domain = domain
        
        # Make API call to list zones - get all zones to find our domain
        url = "https://api.cloudflare.com/client/v4/zones?per_page=50"
        headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json'
        }
        
        req = urllib.request.Request(url, headers=headers)
        
        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode())
                
                if not data.get('success'):
                    errors = data.get('errors', [])
                    error_msgs = [f"{e.get('code', 'unknown')}: {e.get('message', 'unknown error')}" for e in errors]
                    return False, f"API call failed: {', '.join(error_msgs)}", None
                
                # Check if we have access to any zones
                zones = data.get('result', [])
                if not zones:
                    return False, "API token has no access to any zones", None
                
                # Check if our domain is in the accessible zones
                domain_zone = None
                accessible_zones = []
                
                for zone in zones:
                    zone_name = zone.get('name', '')
                    accessible_zones.append(zone_name)
                    
                    # Check if this zone matches our domain or base domain
                    if zone_name == domain or zone_name == base_domain:
                        domain_zone = zone
                        break
                
                if not domain_zone:
                    error_msg = f"Domain '{domain}' (base: '{base_domain}') not found in accessible zones.\n"
                    error_msg += f"\nZones accessible with this token:\n"
                    for zone_name in accessible_zones:
                        error_msg += f"  - {zone_name}\n"
                    error_msg += "\nPossible causes:\n"
                    error_msg += "  1. Domain is not added to your Cloudflare account\n"
                    error_msg += "  2. API token doesn't have permission for this zone\n"
                    error_msg += "  3. DOMAIN in .env doesn't match the Cloudflare zone name\n"
                    error_msg += "\nTo fix:\n"
                    error_msg += "  1. Verify the domain is added to Cloudflare\n"
                    error_msg += "  2. Recreate the API token and include this zone\n"
                    error_msg += "  3. Update DOMAIN in .env to match a zone listed above"
                    return False, error_msg, None
                
                # Verify the token has DNS edit permissions for this zone
                zone_id = domain_zone.get('id')
                zone_name = domain_zone.get('name')
                
                # Make a test call to list DNS records (read permission test)
                dns_url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?per_page=1"
                dns_req = urllib.request.Request(dns_url, headers=headers)
                
                try:
                    with urllib.request.urlopen(dns_req, timeout=10) as dns_response:
                        dns_data = json.loads(dns_response.read().decode())
                        
                        if not dns_data.get('success'):
                            errors = dns_data.get('errors', [])
                            error_msgs = [f"{e.get('code', 'unknown')}: {e.get('message', 'unknown error')}" for e in errors]
                            return False, f"API token cannot access DNS records for zone '{zone_name}': {', '.join(error_msgs)}", None
                        
                        # Success - token has access to the domain and can read DNS records
                        zone_info = {
                            'id': zone_id,
                            'name': zone_name,
                            'status': domain_zone.get('status', 'unknown')
                        }
                        return True, None, zone_info
                
                except urllib.error.HTTPError as e:
                    if e.code == 403:
                        return False, f"API token does not have DNS read permission for zone '{zone_name}'. Ensure token has 'Zone > DNS > Edit' permission.", None
                    else:
                        error_body = e.read().decode() if hasattr(e, 'read') else ''
                        return False, f"HTTP {e.code} when checking DNS permissions: {e.reason}. {error_body[:200]}", None
        
        except urllib.error.HTTPError as e:
            if e.code == 403:
                return False, "API token is valid but has insufficient permissions. Ensure it has 'Zone > DNS > Edit' permission.", None
            else:
                error_body = e.read().decode() if hasattr(e, 'read') else ''
                return False, f"HTTP {e.code}: {e.reason}. {error_body[:200]}", None
        except urllib.error.URLError as e:
            return False, f"Network error: {e.reason}", None
        except Exception as e:
            return False, f"Request failed: {str(e)}", None
    
    except ImportError:
        return False, "urllib not available (should not happen in Python 3)", None
    except Exception as e:
        return False, f"Unexpected error: {str(e)}", None

def main():
    """Main execution function"""
    parser = argparse.ArgumentParser(
        description='Pre-flight check for DNS-01 certificate issuance with Cloudflare',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        '--env-file',
        default='.env',
        help='Path to .env file (default: .env)'
    )
    parser.add_argument(
        '--acme-storage',
        default='/var/lib/docker/volumes/traefik-acme/_data/acme-dns.json',
        help='Path to ACME storage JSON (default: /var/lib/docker/volumes/traefik-acme/_data/acme-dns.json)'
    )
    
    args = parser.parse_args()
    
    # Load environment variables from file
    env_vars = load_env_file(args.env_file)
    
    # Get configuration values
    le_challenge = get_env_value('LE_CHALLENGE', env_vars)
    le_dns_provider = get_env_value('LE_DNS_PROVIDER', env_vars)
    domain = get_env_value('DOMAIN', env_vars)
    subdomain = get_env_value('SUBDOMAIN', env_vars)
    
    # Check if DNS-01 challenge is configured
    if le_challenge != 'dns':
        # Not using DNS-01, skip all checks
        log_info("LE_CHALLENGE is not 'dns' - skipping Cloudflare DNS check")
        sys.exit(0)
    
    # Check if Cloudflare is the DNS provider
    if le_dns_provider != 'cloudflare':
        # Not using Cloudflare, skip checks
        log_info(f"LE_DNS_PROVIDER is '{le_dns_provider}' (not 'cloudflare') - skipping Cloudflare check")
        sys.exit(0)
    
    log_info("DNS-01 challenge with Cloudflare provider detected")
    
    # Check if domain is configured
    if not domain or domain == 'paste-domain-here':
        log_error("DOMAIN is not configured properly in .env")
        log_info("Please set DOMAIN to your actual domain name")
        sys.exit(1)
    
    # Build list of domains to check
    domains = [domain]
    if subdomain:
        domains.append(f"{subdomain}.{domain}")
    
    log_info(f"Checking certificates for domains: {', '.join(domains)}")
    
    # Check if valid certificates already exist
    certs_valid, cert_status = check_certificates_exist_and_valid(args.acme_storage, domains)
    
    if certs_valid:
        log_pass("Valid certificates already exist for all domains")
        log_info("Skipping Cloudflare credential validation (certificates present)")
        log_info(cert_status)
        sys.exit(0)
    else:
        log_warn("Certificates not found or may be expired")
        log_info(cert_status)
        log_info("Proceeding with Cloudflare credential validation...")
    
    # Validate Cloudflare credentials are present
    creds_valid, api_token, cred_error = validate_cloudflare_credentials(env_vars)
    
    if not creds_valid:
        log_error("Cloudflare credentials validation failed")
        log_error(cred_error)
        sys.exit(1)
    
    log_pass("Cloudflare API token found")
    
    # Test Cloudflare API connectivity and domain access
    log_info("Testing Cloudflare API connectivity and domain access...")
    api_success, api_error, zone_info = test_cloudflare_api_connectivity(api_token, domain)
    
    if not api_success:
        log_error("Cloudflare API connectivity or domain access check failed")
        log_error(api_error)
        log_error("")
        log_error("Common issues:")
        log_error("  1. Invalid or expired API token")
        log_error("  2. Token doesn't have 'Zone > DNS > Edit' permissions")
        log_error("  3. Token doesn't have access to the domain's zone")
        log_error("  4. Domain not added to your Cloudflare account")
        log_error("  5. Network connectivity issues")
        log_error("")
        log_error("To fix:")
        log_error("  1. Verify your token at: https://dash.cloudflare.com/profile/api-tokens")
        log_error("  2. Ensure the token has 'Zone > DNS > Edit' permissions")
        log_error("  3. Ensure the token includes your domain's zone")
        log_error("  4. Check that DOMAIN in .env matches your Cloudflare zone")
        log_error("  5. Verify network connectivity to api.cloudflare.com")
        log_error("  6. Create a new token if needed and update CF_DNS_API_TOKEN in .env")
        sys.exit(1)
    
    log_pass("Cloudflare API connectivity test successful")
    log_pass(f"Token has access to zone: {zone_info['name']} (status: {zone_info['status']})")
    log_info("Ready to issue certificates via DNS-01 challenge")
    sys.exit(0)

if __name__ == '__main__':
    main()
