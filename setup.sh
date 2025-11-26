#!/bin/bash
# File: setup-nocodb-ipv6-fixed.sh
# Run as root (or with sudo) – Fixes IPv6 URL parsing in NC_PUBLIC_URL for NocoDB Docker

set -e  # Stop on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting NocoDB setup with IPv6 URL fix...${NC}"

# 1. Create the folder if it doesn't exist
echo "Creating /root/nocodb folder..."
mkdir -p /root/nocodb
cd /root/nocodb

# 2. Detect public IP (prefer IPv4, fallback to IPv6 with brackets)
echo "Detecting public IP..."
PUBLIC_IP4=$(curl -s -4 ifconfig.me 2>/dev/null)
if [ -n "$PUBLIC_IP4" ] && [[ ! "$PUBLIC_IP4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  PUBLIC_IP4=""  # Invalid if not IPv4 format
fi

if [ -n "$PUBLIC_IP4" ]; then
  PUBLIC_IP="$PUBLIC_IP4"
  echo "Using IPv4: $PUBLIC_IP"
else
  PUBLIC_IP6=$(curl -s -6 ifconfig.me 2>/dev/null)
  if [[ "$PUBLIC_IP6" =~ ^[0-9a-fA-F:]+$ ]] && [ ${#PUBLIC_IP6} -gt 4 ]; then  # Basic IPv6 check
    PUBLIC_IP="[${PUBLIC_IP6}]"  # Bracket for URL
    echo "Using IPv6 (bracketed): $PUBLIC_IP"
  else
    PUBLIC_IP="localhost"
    echo -e "${RED}Warning: Could not detect valid public IP. Using 'localhost' – update NC_PUBLIC_URL manually!${NC}"
  fi
fi
PUBLIC_URL="http://${PUBLIC_IP}:8080"

# 3. Validate the URL with Node.js (quick test)
echo "Validating URL: $PUBLIC_URL"
node -e "try { new URL('$PUBLIC_URL'); console.log('URL valid!'); } catch(e) { console.error('URL invalid:', e.message); process.exit(1); }" || {
  echo -e "${RED}URL validation failed. Edit .env manually and set NC_PUBLIC_URL to a valid format (e.g., http://[your-ipv6]:8080).${NC}"
  exit 1
}

# 4. Generate a strong random JWT secret (64 characters, base64)
echo "Generating strong JWT secret..."
NC_AUTH_JWT_SECRET=$(openssl rand -base64 64 | tr '+/' '-_' | cut -c1-64)

# 5. Write secure .env file
cat > .env << EOF
# NocoDB Environment - Auto-generated on $(date)
# =============================================
# Security: JWT secret for auth tokens
NC_AUTH_JWT_SECRET=${NC_AUTH_JWT_SECRET}

# Database: SQLite with absolute file URL to avoid "Invalid URL" errors
NC_DB=sqlite
NC_DB_URL=file:///usr/app/data/nocodb.sqlite

# Public URL: Fixed for IPv6 (bracketed) – Required for emails, API links, etc.
# Update to your domain/HTTPS later! (e.g., https://your-domain.com)
NC_PUBLIC_URL=${PUBLIC_URL}

# Optional: Uncomment/add if using SMTP for emails
# NC_SMTP_HOST=smtp.gmail.com
# NC_SMTP_PORT=587
# NC_SMTP_SECURE=false  # true for 465
# NC_SMTP_USER=your-email@gmail.com
# NC_SMTP_PASS=your-app-password
# NC_FROM_EMAIL=noreply@your-domain.com

# Optional: For production security
# NC_DISABLE_SIGNUP=true  # Disable public signups
EOF

echo -e "${GREEN}Generated .env with IPv6 fix (NC_PUBLIC_URL: ${PUBLIC_URL}).${NC}"

# 6. Create docker-compose.yml (uses latest bug-fix image)
cat > docker-compose.yml << 'EOF'
version: "3.7"

services:
  nocodb:
    image: nocodb/nocodb:0.263.1  # Latest bug-fix release (fixes URL issues)
    container_name: nocodb
    restart: unless-stopped
    ports:
      - "8080:8080"
    env_file:
      - .env
    environment:
      # Explicitly set for fallback (but .env overrides)
      NC_DB: "sqlite"
    volumes:
      - ./data:/usr/app/data  # Persist SQLite DB here
    networks:
      - nocodb-net

networks:
  nocodb-net:
    driver: bridge

volumes:
  data:
EOF

# 7. Secure .env (root-only read/write)
chmod 600 .env

# 8. Clean start: Stop old, recreate data dir
echo "Cleaning up old setup..."
docker compose down >/dev/null 2>&1 || true
rm -rf data  # Fresh start (remove if you want to keep data)
mkdir -p data
chmod 777 data  # Docker write access

# 9. Start NocoDB
echo "Starting NocoDB..."
docker compose up -d

# 10. Wait and verify startup
sleep 15
if docker ps | grep -q nocodb; then
  LOGS=$(docker logs nocodb --tail 30 2>/dev/null)
  if echo "$LOGS" | grep -q "NocoDB started on"; && ! echo "$LOGS" | grep -q "Invalid URL"; then
    echo -e "${GREEN}Success! NocoDB is running with IPv6 fix.${NC}"
    echo "URL: ${PUBLIC_URL}"
    echo "Dashboard: ${PUBLIC_URL}/dashboard"
    echo ""
    echo "Full logs: docker logs -f nocodb"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "- Access ${PUBLIC_URL} and complete setup."
    echo "- For production: Add NGINX/SSL, update NC_PUBLIC_URL to https://your-domain.com (avoids IPv6 issues)."
    echo "- Backup: rsync -a /root/nocodb/ /backup/"
    echo "- Test IPv6 access: curl -6 '${PUBLIC_URL}'"
  else
    echo -e "${RED}Startup incomplete. Recent logs:${NC}"
    echo "$LOGS"
    echo -e "${RED}If 'Invalid URL' persists, manually edit .env and restart: docker compose restart${NC}"
  fi
else
  echo -e "${RED}Container failed to start. Check: docker logs nocodb${NC}"
fi
