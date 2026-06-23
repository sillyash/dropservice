#!/usr/bin/env bash
# Deploy dropservice to /opt/dropservice with nginx + TLS (Cloudflare DNS challenge).
#
# Usage:
#   DOMAIN=drop.example.com sudo -E ./setup.sh
#
# Prerequisites:
#   - Debian/Ubuntu server
#   - Cloudflare API token with Zone:DNS:Edit permission
#   - Create /etc/letsencrypt/cloudflare.ini before running:
#       dns_cloudflare_api_token = <your-token>
#     then: chmod 600 /etc/letsencrypt/cloudflare.ini
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
DOMAIN="${DOMAIN:-}"
APP_DIR="/opt/dropservice"
UPLOAD_DIR="/srv/drops"
SERVICE_USER="www-data"
PORT=8080
CF_CREDENTIALS="${CF_CREDENTIALS:-/etc/letsencrypt/cloudflare.ini}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ─────────────────────────────────────────────────────────────────────────────

info() { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
ok()   { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
die()  { printf '\e[1;31m[ERR ]\e[0m  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo -E ./setup.sh"
[[ -n "$DOMAIN" ]] || die "Set DOMAIN before running: DOMAIN=drop.example.com sudo -E ./setup.sh"

# ── 1. System packages ────────────────────────────────────────────────────────
info "Installing system packages..."
apt-get update -q
apt-get install -y -q nginx certbot python3-certbot-dns-cloudflare rsync

# ── 2. uv ────────────────────────────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
    info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add common install locations to PATH for this session
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi
command -v uv &>/dev/null || die "uv not found in PATH after install — open a new shell and re-run"

# ── 3. Deploy application files ───────────────────────────────────────────────
info "Deploying files to $APP_DIR..."
mkdir -p "$APP_DIR"
rsync -a --exclude='.git' --exclude='.venv' "$SCRIPT_DIR/" "$APP_DIR/"
chown -R root:root "$APP_DIR"

# ── 4. Python dependencies ────────────────────────────────────────────────────
info "Installing Python dependencies..."
(cd "$APP_DIR" && uv sync)

# ── 5. Environment file ───────────────────────────────────────────────────────
if [[ ! -f "$APP_DIR/.env" ]]; then
    info "Creating .env from example..."
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
fi

# ── 6. Upload directory ───────────────────────────────────────────────────────
info "Creating upload directory $UPLOAD_DIR..."
mkdir -p "$UPLOAD_DIR"
chown "$SERVICE_USER:$SERVICE_USER" "$UPLOAD_DIR"

# ── 7. systemd service ────────────────────────────────────────────────────────
info "Installing drop.service..."
cat > /etc/systemd/system/drop.service <<EOF
[Unit]
Description=File drop service
After=network.target

[Service]
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/.venv/bin/python main.py
Restart=always
User=$SERVICE_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable drop
systemctl restart drop
ok "drop.service enabled and running"

# ── 8. TLS certificate ────────────────────────────────────────────────────────
if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
    info "Obtaining TLS certificate for $DOMAIN..."
    [[ -f "$CF_CREDENTIALS" ]] || die "Missing Cloudflare credentials: $CF_CREDENTIALS\nCreate it with:\n  dns_cloudflare_api_token = <your-token>\nthen: chmod 600 $CF_CREDENTIALS"
    chmod 600 "$CF_CREDENTIALS"
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CF_CREDENTIALS" \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "admin@${DOMAIN#*.}"
    ok "Certificate obtained"
else
    ok "Certificate already present — skipping"
fi

# ── 9. nginx ──────────────────────────────────────────────────────────────────
info "Configuring nginx for $DOMAIN..."
cat > /etc/nginx/sites-available/drop <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    client_max_body_size 0;
    proxy_read_timeout 600;
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/drop /etc/nginx/sites-enabled/drop
nginx -t
systemctl reload nginx
ok "nginx configured and reloaded"

# ── Done ──────────────────────────────────────────────────────────────────────
ok "Setup complete — https://$DOMAIN"
