#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${DOMAIN:-${WEBUI_DOMAIN:-}}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
WEBROOT="${WEBROOT:-/var/www/miningcore-webui}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/contrib/webui-simple"
BACKUP_DIR="/root/backups/pre-webui-${DOMAIN}-$(date +%Y%m%d-%H%M%S)"
log(){ printf "\n==> %s\n" "$*"; }

if [[ -z "$DOMAIN" ]]; then
  echo "DOMAIN or WEBUI_DOMAIN is required for HTTPS WebUI installation" >&2
  exit 1
fi
if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
  echo "LETSENCRYPT_EMAIL is required for Let's Encrypt HTTPS" >&2
  exit 1
fi
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "WebUI source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

log "Creating backup at ${BACKUP_DIR}"
sudo mkdir -p "$BACKUP_DIR"
for p in /etc/nginx /etc/letsencrypt /etc/ufw /etc/fail2ban /etc/sysctl.d/99-aalnase-pool-hardening.conf /etc/miningcore/config.json "$WEBROOT"; do
  if sudo test -e "$p"; then
    sudo tar --warning=no-file-changed -C / -czf "$BACKUP_DIR/$(echo "$p" | sed "s#^/##;s#/#_#g").tar.gz" "${p#/}" || true
  fi
done
{
  echo "# date"; date -Is
  echo "# hostname"; hostname -f || hostname
  echo "# services"; systemctl status miningcore multiflexd nginx --no-pager || true
  echo "# ports"; sudo ss -ltnp || true
  echo "# ufw"; sudo ufw status verbose || true
  echo "# local api pools"; curl -fsS http://127.0.0.1:4000/api/pools || true
} | sudo tee "$BACKUP_DIR/status-before.txt" >/dev/null
sudo find "$BACKUP_DIR" -type f -maxdepth 1 -exec sha256sum {} \; | sudo tee "$BACKUP_DIR/SHA256SUMS.txt" >/dev/null
log "Backup ready: ${BACKUP_DIR}"

log "Installing packages"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx curl certbot python3-certbot-nginx ca-certificates rsync

log "Installing simple MFLEX WebUI"
sudo mkdir -p "$WEBROOT"
sudo rsync -a --delete "$SOURCE_DIR/" "$WEBROOT/"
sudo chown -R www-data:www-data "$WEBROOT"
sudo find "$WEBROOT" -type d -exec chmod 755 {} \;
sudo find "$WEBROOT" -type f -exec chmod 644 {} \;

log "Configuring Nginx"
sudo tee /etc/nginx/sites-available/miningcore-webui >/dev/null <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${WEBROOT};
    index index.html;

    access_log /var/log/nginx/miningcore-webui-access.log;
    error_log /var/log/nginx/miningcore-webui-error.log;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:4000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
        add_header X-Backend "miningcore" always;
    }

    location ~ /\\. {
        deny all;
    }
}
NGINX
sudo ln -sf /etc/nginx/sites-available/miningcore-webui /etc/nginx/sites-enabled/miningcore-webui
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

log "Opening firewall for HTTP/HTTPS"
sudo ufw allow 80/tcp comment "HTTP for WebUI and LetsEncrypt" >/dev/null
sudo ufw allow 443/tcp comment "HTTPS WebUI" >/dev/null
sudo ufw status verbose

log "Checking HTTP before certbot"
curl -I --max-time 15 "http://${DOMAIN}/" || true
curl -fsS --max-time 15 "http://${DOMAIN}/api/pools" | head -c 1000 || true; echo

log "Issuing HTTPS certificate"
PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org || true)"
DOMAIN_IPS="$(getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
if [[ -z "$PUBLIC_IP" || " $DOMAIN_IPS " != *" $PUBLIC_IP "* ]]; then
  echo "Cannot issue HTTPS certificate: ${DOMAIN} must resolve to this server before install continues." >&2
  echo "This server public IPv4: ${PUBLIC_IP:-unknown}" >&2
  echo "Domain IPv4 records: ${DOMAIN_IPS:-none}" >&2
  exit 1
fi
sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$LETSENCRYPT_EMAIL" --redirect
sudo nginx -t
sudo systemctl reload nginx

log "Final verification"
curl -I --max-time 20 "https://${DOMAIN}/"
echo
curl -fsS --max-time 20 "https://${DOMAIN}/api/pools" | python3 -m json.tool | head -120 || true
printf "\nWEBUI_URL=https://%s/\nBACKUP_DIR=%s\n" "$DOMAIN" "$BACKUP_DIR"
