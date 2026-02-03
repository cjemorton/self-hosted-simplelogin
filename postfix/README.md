# Postfix Mail Server Configuration

This directory contains the Docker configuration for the Postfix mail server used by SimpleLogin.

## Directory Structure

```
postfix/
├── Dockerfile              # Multi-stage Dockerfile for building the Postfix image
├── docker-entrypoint.sh   # Entrypoint script for configuring Postfix at runtime
├── conf.d/                # Postfix configuration snippets
└── templates/             # Configuration file templates
```

## What is Postfix?

[Postfix](http://www.postfix.org/) is a free and open-source mail transfer agent (MTA) that routes and delivers email. In SimpleLogin, Postfix:

- Receives incoming emails on ports 25 and 587
- Forwards emails to SimpleLogin for alias processing
- Sends outgoing emails from SimpleLogin aliases
- Enforces TLS for secure email transmission

## Build Process

The Postfix Docker image is built locally during the setup process:

```bash
docker compose build postfix
```

Or automatically when running:

```bash
bash scripts/up.sh
```

## Configuration

Postfix is configured through:

1. **Environment Variables** - Loaded from your `.env` file in the repository root
   - `DOMAIN` - Your email domain
   - `SUBDOMAIN` - Subdomain for the web app (default: app)
   - `SPAMHAUS_DQS_KEY` - Optional Spamhaus blocklist key

2. **Runtime Configuration** - Applied by `docker-entrypoint.sh`
   - TLS certificate configuration
   - Domain-specific settings
   - Integration with SimpleLogin email handler

3. **Static Configuration** - Files in `conf.d/` and `templates/`
   - Postfix main.cf and master.cf templates
   - Virtual domain and alias configurations

## Important Notes

- **Do not delete this directory** - It is required for building the Postfix Docker image
- **Do not modify files** unless you understand Postfix configuration
- The Postfix container depends on the certificate exporter for TLS certificates
- Postfix must be restarted when TLS certificates are renewed

## Troubleshooting

If you see errors about the `postfix` directory not being found:

1. **Verify you're in the repository root:**
   ```bash
   pwd  # Should show /opt/simplelogin or your installation directory
   ls -la postfix/  # Should show Dockerfile and other files
   ```

2. **Ensure your repository clone is complete:**
   ```bash
   git status  # Check for any issues
   ```

3. **Check Docker build context:**
   - The build context is set in `config/postfix-compose.yaml`
   - It should be `context: ./postfix` (relative to repository root)

For more help, see the main [Troubleshooting Guide](../docs/TROUBLESHOOTING.md).

## Related Components

- **SimpleLogin Email Handler** - Processes incoming emails forwarded by Postfix
- **Certificate Exporter** - Extracts TLS certificates from Traefik for Postfix
- **Traefik** - Reverse proxy that handles TLS certificate issuance

## Resources

- [Postfix Documentation](http://www.postfix.org/documentation.html)
- [SimpleLogin Email Flow](../docs/ARCHITECTURE_DIAGRAM.md)
