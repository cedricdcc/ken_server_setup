#!/bin/bash
# File: setup-nocodb-with-secret.sh
# Run as root (or with sudo) in your server

set -e  # Stop on any error

# 1. Create the folder if it doesn't exist
echo "Creating /root/nocodb folder..."
mkdir -p /root/nocodb
cd /root/nocodb

# 2. Generate a strong random JWT secret (64 characters, URL-safe)
echo "Generating strong JWT secret..."
NC_AUTH_JWT_SECRET=$(openssl rand -base64 64 | tr '+/' '-_' | cut -c1-64)
echo "Generated secret (saved securely below)"

# 3. Write it to a .env file (never visible in docker-compose.yml)
cat > /root/nocodb/.env << EOF
# NocoDB Security - Auto-generated on $(date)
NC_AUTH_JWT_SECRET=${NC_AUTH_JWT_SECRET}
EOF

# 4. Create or update the docker-compose.yml to use the .env file
cat > /root/nocodb/docker-compose.yml << 'EOF'
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
      NC_DB: "sqlite"
    volumes:
      - ./data:/usr/app/data

volumes:
  data:
EOF

# 5. Make .env file readable only by root (security best practice)
chmod 600 /root/nocodb/.env

# 6. Start (or restart) NocoDB
echo "Starting NocoDB with secure configuration..."
docker compose down >/dev/null 2>&1 || true
docker compose up -d

# 7. Final success message
echo "=================================="
echo "NocoDB is now running securely!"
echo "URL: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):8080"
echo ""
echo "Your JWT secret is safely stored in /root/nocodb/.env"
echo "Never share it and never commit it to Git!"
echo "=================================="