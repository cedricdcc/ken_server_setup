#!/bin/bash
# File: setup-nocodb-secure-fixed.sh
# Run as root (or with sudo) in your server
# Fixes "Invalid URL" by setting NC_PUBLIC_URL and absolute NC_DB_URL

set -e  # Stop on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting secure NocoDB setup with URL fixes...${NC}"

# 1. Create the folder if it doesn't exist
echo "Creating /root/nocodb folder..."
mkdir -p /root/nocodb
cd /root/nocodb

# 2. Detect public IP for NC_PUBLIC_URL
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
if [ "$PUBLIC_IP" = "localhost" ]; then
  echo -e "${RED}Warning: Could not detect public IP. Using 'localhost' – update NC_PUBLIC_URL manually later!${NC}"
fi
PUBLIC_URL="http://${PUBLIC_IP}:8080"

# 3. Generate a strong random JWT secret (64 characters, base64)
echo "Generating strong JWT secret..."
NC_AUTH_JWT_SECRET=$(openssl rand -base64 64 | tr '+/' '-_' | cut -c1-64)

# 4. Write secure .env file
cat > .env << EOF
# NocoDB Environment - Auto-generated on $(date)
# =============================================
# Security: JWT secret for auth tokens
NC_AUTH_JWT_SECRET=${NC_AUTH_JWT_SECRET}

# Database: SQLite with absolute file URL to avoid "Invalid URL" errors
NC_DB=sqlite
NC_DB_URL=file:///usr/app/data/nocodb.sqlite

# Public URL: Required for emails, API links, etc. Update to your domain/HTTPS later!
# Format: http://your-ip:8080 or https://your-domain.com
NC_PUBLIC_URL=${PUBLIC_URL}

# Optional: Uncomment/add if using SMTP for emails
# NC_SMTP_HOST=smtp.gmail.com
# NC_SMTP_PORT=587
# NC_SMTP_SECURE=false  # true for 465
# NC_SMTP_USER=your-email@gmail.com
# NC_SMTP_PASS=your-app-password
# NC_FROM_EMAIL=noreply@your-domain.com

# Optional: For production, add more security
# NC_DISABLE_SIGNUP=true  # Disable public signups
EOF

echo -e "${GREEN}Generated .env with fixes (NC_PUBLIC_URL: ${PUBLIC_URL}).${NC}"

# 5. Create docker-compose.yml (loads .env automatically)
cat > docker-compose.yml << 'EOF'
version: "3.7"

services:
  nocodb:
    image: nocodb/nocodb:latest
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

# 6. Secure .env (root-only read/write)
chmod 600 .env

# 7. Clean start: Stop old container, remove old data if needed (comment out if you want to keep data)
echo "Cleaning up old setup..."
docker compose down -v  # -v removes volumes (uncomment if you want fresh start)
mkdir -p data  # Recreate data dir
chmod 777 data  # Allow Docker to write (fixes SQLite permission issues)

# 8. Start NocoDB
echo "Starting NocoDB..."
docker compose up -d

# 9. Wait and check startup
sleep 10
if docker ps | grep -q nocodb; then
  LOGS=$(docker logs nocodb --tail 20)
  if echo "$LOGS" | grep -q "NocoDB started on"; then
    echo -e "${GREEN}Success! NocoDB is running.${NC}"
    echo "URL: ${PUBLIC_URL}"
    echo "Dashboard: ${PUBLIC_URL}/dashboard"
    echo ""
    echo "Check full logs: docker logs -f nocodb"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "- Access http://${PUBLIC_IP}:8080 and complete setup."
    echo "- For production: Add NGINX/SSL, update NC_PUBLIC_URL to https://your-domain.com"
    echo "- Backup: rsync -a /root/nocodb/ /backup/"
    echo "- If error persists: Run 'docker compose exec nocodb env | grep NC_' and share output."
  else
    echo -e "${RED}Startup failed. Recent logs:${NC}"
    echo "$LOGS"
  fi
else
  echo -e "${RED}Container failed to start. Check: docker logs nocodb${NC}"
fi
