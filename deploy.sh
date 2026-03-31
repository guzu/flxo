#!/bin/bash
# Deployment script — do NOT commit (add deploy.sh to .gitignore)
# Usage: ./deploy.sh
# Cible : root@10.1.30.10, thttpd sur /var/www/http/, sources dans /root/flxo/

set -euo pipefail

REMOTE="root@10.1.30.10"
REMOTE_DIR="/root/flxo"
API_URL="http://10.1.30.10:8080"
FRONTEND_URL="http://10.1.30.10"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 1. Build frontend ────────────────────────────────────────────────────────
echo "==> Build du frontend..."
cd "$SCRIPT_DIR/frontend"
VITE_API_URL="$API_URL" npm run build
cd "$SCRIPT_DIR"

# ─── 2. Build du venv Python dans un conteneur Alpine ───────────────────────
echo "==> Build du venv Python dans un conteneur Alpine..."
UV_PYTHON_DIR="$SCRIPT_DIR/.deploy-uv-python"
rm -rf "$UV_PYTHON_DIR"
mkdir -p "$UV_PYTHON_DIR"
docker run --rm \
  -v "$SCRIPT_DIR/backend:/root/flxo/backend" \
  -v "$UV_PYTHON_DIR:/root/.local/share/uv/python" \
  -w /root/flxo/backend \
  alpine:3.12 \
  sh -c "
    set -e
    apk add --no-cache gcc g++ musl-dev make file curl libffi-dev openssl-dev
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    uv python install 3.12
    rm -rf .venv
    uv sync --locked --no-editable --no-dev --no-group dev --no-cache --python 3.12
  "

# ─── 3. Création des répertoires distants ───────────────────────────────────
echo "==> Création des répertoires distants..."
sshvm "$REMOTE" mkdir -p "$REMOTE_DIR/backend"

# ─── 4. Sync backend + venv + Python ───────────────────────────────────────
echo "==> Sync du backend et du venv..."
rsync -az --delete \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  -e sshvm \
  "$SCRIPT_DIR/backend/" "$REMOTE:$REMOTE_DIR/backend/"

echo "==> Sync du runtime Python..."
rsync -az \
  -e sshvm \
  "$UV_PYTHON_DIR/" "$REMOTE:/root/.local/share/uv/python/"

# ─── 5. Déploiement du frontend → /var/www/http/ ───────────────────────────
echo "==> Déploiement du frontend..."
rsync -az --delete \
  -e sshvm \
  "$SCRIPT_DIR/frontend/dist/" "$REMOTE:/var/www/http/"

# ─── 5b. Copie des assets offices (logo, floor plan) ─────────────────────
echo "==> Copie des assets offices..."
STATIC_FILES=$(python3 -c "
import sqlite3, json
conn = sqlite3.connect('$SCRIPT_DIR/backend/flxo.db')
for row in conn.execute('SELECT properties FROM office'):
    props = json.loads(row[0]) if row[0] else {}
    for k in ('logo_url', 'floor_plan_url'):
        v = props.get(k, '')
        if v:
            print(v.lstrip('/'))
conn.close()
")
for f in $STATIC_FILES; do
  src="$SCRIPT_DIR/frontend/public/$f"
  if [ -f "$src" ]; then
    echo "  -> $f"
    rsync -az -e sshvm "$src" "$REMOTE:/var/www/http/$f"
  else
    echo "  ⚠ $f introuvable dans frontend/public/"
  fi
done

# ─── 6. Configuration distante ────────────────────────────────────────────
echo "==> Configuration distante..."
sshvm "$REMOTE" bash << ENDSSH
set -euo pipefail
source /root/.profile

# Config — écrasé à chaque deploy
echo "  -> Écriture de config.toml..."
SECRET_KEY=\$(python3 -c "import secrets; print(secrets.token_hex(32))")
cat > "$REMOTE_DIR/backend/config.toml" << EOF
[app]
secret_key = "\$SECRET_KEY"
bind = "0.0.0.0"
port = 8080
access_url = "$API_URL"
allowed_origins = "$FRONTEND_URL"

[db]
driver = "sqlite"
host = "$REMOTE_DIR/backend/flxo.db"

[oauth]
client_id = ""
client_secret = ""
EOF

# Service OpenRC
if [ ! -f /etc/init.d/flxo ]; then
  echo "  -> Création du service OpenRC..."
  cat > /etc/init.d/flxo << 'EOF'
#!/sbin/openrc-run
name="flxo"
description="FlxO backend API"
directory="/root/flxo/backend"
command="/root/flxo/backend/.venv/bin/uvicorn"
command_args="flxo:app --host 0.0.0.0 --port 8080"
command_background=true
pidfile="/run/flxo.pid"
output_log="/var/log/flxo.log"
error_log="/var/log/flxo.log"

depend() {
    need net
}
EOF
  chmod +x /etc/init.d/flxo
  rc-update add flxo default
fi

# Démarrage / rechargement
if rc-service flxo status > /dev/null 2>&1; then
  echo "  -> Redémarrage du service..."
  rc-service flxo restart
else
  echo "  -> Démarrage du service..."
  rc-service flxo start
fi

echo "==> Déploiement terminé."
echo "    Frontend : $FRONTEND_URL"
echo "    Backend  : $API_URL"
ENDSSH
