#!/bin/bash
# Run this ONCE on the server before starting nginx for the first time.
# It creates dummy self-signed certs so nginx can start, then replaces
# them with real Let's Encrypt certificates via certbot webroot challenge.
#
# Usage:
#   chmod +x infrastructure/nginx/init-letsencrypt.sh
#   ./infrastructure/nginx/init-letsencrypt.sh

set -e

DOMAINS=(example.ir example2.ir)
EMAIL="your-email@example.com"   # ← change to your real email for expiry notices
DATA_PATH="./letsencrypt"         # named volume mount path on host (if using bind mount)

# If using docker named volumes, certbot writes to /etc/letsencrypt inside the container.
# This script uses docker compose exec / run to operate inside the containers.

echo "### Creating dummy certificates ..."
for domain in "${DOMAINS[@]}"; do
    mkdir -p "${DATA_PATH}/live/${domain}"
    docker compose run --rm --entrypoint "\
        openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
            -keyout '/etc/letsencrypt/live/${domain}/privkey.pem' \
            -out '/etc/letsencrypt/live/${domain}/fullchain.pem' \
            -subj '/CN=${domain}'" \
        certbot
done

echo "### Starting nginx with dummy certs ..."
docker compose up --detach nginx

echo "### Requesting real certificates from Let's Encrypt ..."
for domain in "${DOMAINS[@]}"; do
    docker compose run --rm --entrypoint "\
        certbot certonly --webroot \
            -w /var/www/certbot \
            --email ${EMAIL} \
            --agree-tos \
            --no-eff-email \
            -d ${domain}" \
        certbot
done

echo "### Reloading nginx with real certificates ..."
docker compose exec nginx nginx -s reload

echo "### Done. Certificates are valid. nginx is running."
echo ""
echo "Renewal is handled automatically by the certbot container (every 12h)."
