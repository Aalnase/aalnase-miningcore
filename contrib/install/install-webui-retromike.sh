#!/usr/bin/env bash
set -euo pipefail
DOMAIN="eu.go-poolmining.com"
WEBROOT="/var/www/miningcore-webui"
BACKUP_DIR="/root/backups/pre-webui-${DOMAIN}-$(date +%Y%m%d-%H%M%S)"
log(){ printf "\n==> %s\n" "$*"; }

log "Creating backup at ${BACKUP_DIR}"
sudo mkdir -p "$BACKUP_DIR"
for p in /etc/nginx /etc/letsencrypt /etc/ufw /etc/fail2ban /etc/sysctl.d/99-aalnase-pool-hardening.conf /etc/miningcore/config.json /var/www; do
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
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx git curl certbot python3-certbot-nginx ca-certificates

log "Installing/updating Retro-Mike WebUI"
sudo rm -rf "${WEBROOT}.new"
sudo git clone --depth 1 https://github.com/TheRetroMike/Miningcore.WebUI.git "${WEBROOT}.new"
if sudo test -d "$WEBROOT"; then
  sudo mv "$WEBROOT" "${WEBROOT}.bak.$(date +%Y%m%d-%H%M%S)"
fi
sudo mv "${WEBROOT}.new" "$WEBROOT"
sudo chown -R www-data:www-data "$WEBROOT"
sudo find "$WEBROOT" -type d -exec chmod 755 {} \;
sudo find "$WEBROOT" -type f -exec chmod 644 {} \;

log "Inspecting WebUI config files"
sudo find "$WEBROOT" -maxdepth 3 -type f \( -name "*.js" -o -name "*.html" -o -name "*.json" \) | sudo tee "$BACKUP_DIR/webui-files.txt" >/dev/null
sudo grep -RIn "var WebURL\|var API\|stratumAddress\|API_BASE_URL\|localhost\|4000\|miningcore" "$WEBROOT" | sudo tee "$BACKUP_DIR/webui-config-matches-before.txt" >/dev/null || true

log "Configuring WebUI domain/API/stratum strings when present"
# Older Retro-Mike WebUI uses js/miningcore.js globals. Patch if found.
if sudo test -f "$WEBROOT/js/miningcore.js"; then
  sudo python3 - <<PY
from pathlib import Path
p=Path("$WEBROOT/js/miningcore.js")
s=p.read_text()
repls={
    "var WebURL = window.location.protocol + \"//\" + window.location.hostname + \"/\";": "var WebURL = \"https://$DOMAIN/\";",
    "var API = WebURL + \"api/\";": "var API = \"https://$DOMAIN/api/\";",
    "var stratumAddress = \"stratum+tcp://\" + window.location.hostname + \":\";": "var stratumAddress = \"stratum+tcp://$DOMAIN:\";",
}
for old,new in repls.items():
    s=s.replace(old,new)
p.write_text(s)
PY
fi
# Generic fallback replacements for common hard-coded examples.
sudo grep -RIl "umbrel.local\|retro-mike-miningcore_server_1\|localhost:4000\|127.0.0.1:4000" "$WEBROOT" | while read -r f; do
  sudo sed -i \
    -e "s#http://retro-mike-miningcore_server_1:4000/api#https://${DOMAIN}/api#g" \
    -e "s#http://localhost:4000/api#https://${DOMAIN}/api#g" \
    -e "s#http://127.0.0.1:4000/api#https://${DOMAIN}/api#g" \
    -e "s#umbrel.local#${DOMAIN}#g" "$f"
done
sudo chown -R www-data:www-data "$WEBROOT"

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
sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
sudo nginx -t
sudo systemctl reload nginx

log "Final verification"
curl -I --max-time 20 "https://${DOMAIN}/"
echo
curl -fsS --max-time 20 "https://${DOMAIN}/api/pools" | python3 -m json.tool | head -120
printf "\nBACKUP_DIR=%s\n" "$BACKUP_DIR"
