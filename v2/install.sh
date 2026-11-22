#!/usr/bin/env bash
# Receipt relay installer for the PasarGuard subscription page ("online renewal" tab).
# Usage: sudo bash install.sh        (first run = install, later runs = update / uninstall menu)
set -euo pipefail

APP_DIR=/opt/receipt
CONF="$APP_DIR/receipt.conf"
SERVICE=receipt
UNIT="/etc/systemd/system/$SERVICE.service"
PANEL_ENV=/opt/pasarguard/.env
PORT=19001   # must match the port in index.html

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { read -r -p "$1" "$2" </dev/tty; }

[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo bash install.sh"
for c in python3 curl systemctl; do command -v "$c" >/dev/null 2>&1 || die "$c is required"; done

write_relay() {
  mkdir -p "$APP_DIR"
  cat > "$APP_DIR/receipt.py" <<'PYEOF'
#!/usr/bin/env python3
"""Receipt relay: takes a receipt photo from the subscription page and sends it
to your Telegram bot with the sender's username as the caption.
Needs only Python 3.8+ (standard library). Secrets live in receipt.conf (chmod 600).
Serves HTTPS itself (using the panel's certificate) so no web server is needed."""
import json
import os
import pwd
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONF = os.environ.get('RECEIPT_CONF') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'receipt.conf')


def load_conf(path):
    if os.stat(path).st_mode & 0o077:
        sys.exit('%s is readable by other users. Run: chmod 600 %s' % (path, path))
    cfg = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                cfg[k.strip()] = v.strip()
    return cfg


cfg = load_conf(CONF)
BOT_TOKEN = cfg['BOT_TOKEN']
CHAT_ID = cfg['CHAT_ID']
PANEL_URL = cfg.get('PANEL_URL', '').rstrip('/')
HOST = cfg.get('HOST', '0.0.0.0')
PORT = int(cfg.get('PORT', '19001'))
SSL_CERT = cfg.get('SSL_CERT', '')
SSL_KEY = cfg.get('SSL_KEY', '')
DROP_USER = cfg.get('DROP_USER', 'receipt')
MAX_BYTES = int(cfg.get('MAX_MB', '8')) * 1024 * 1024
USER_LIMIT = int(cfg.get('USER_LIMIT', '3'))
USER_WINDOW = int(cfg.get('USER_WINDOW_HOURS', '12')) * 3600
IP_LIMIT_PER_HOUR = int(cfg.get('IP_LIMIT_PER_HOUR', '30'))
HITS = {}


def over(key, limit, window):
    now = time.time()
    HITS[key] = [t for t in HITS.get(key, []) if now - t < window]
    return len(HITS[key]) >= limit


def record(key):
    HITS.setdefault(key, []).append(time.time())


def sniff(data):
    if data[:3] == b'\xff\xd8\xff':
        return 'jpg', 'image/jpeg'
    if data[:4] == b'\x89PNG':
        return 'png', 'image/png'
    if data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        return 'webp', 'image/webp'
    return None


def get_username(sub_path, fallback):
    """With PANEL_URL set, the username comes from the panel (cannot be faked)."""
    if not PANEL_URL:
        return fallback or None
    if not re.fullmatch(r'/[A-Za-z0-9_\-./%~]{1,400}', sub_path or '') or '..' in sub_path:
        return None
    try:
        ctx = None
        if re.match(r'https://(127\.0\.0\.1|localhost)(:|/|$)', PANEL_URL):
            ctx = ssl._create_unverified_context()  # loopback to our own panel
        req = urllib.request.Request(PANEL_URL + sub_path.rstrip('/') + '/info', headers={'Accept': 'application/json'})
        with urllib.request.urlopen(req, timeout=8, context=ctx) as r:
            return str(json.load(r).get('username') or '') or None
    except Exception:
        return None


def send_photo(photo, ext, mime, caption):
    b = uuid.uuid4().hex
    body = b''
    for k, v in (('chat_id', CHAT_ID), ('caption', caption)):
        body += ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (b, k, v)).encode('utf-8')
    body += ('--%s\r\nContent-Disposition: form-data; name="photo"; filename="receipt.%s"\r\n'
             'Content-Type: %s\r\n\r\n' % (b, ext, mime)).encode() + photo + b'\r\n'
    body += ('--%s--\r\n' % b).encode()
    req = urllib.request.Request(
        'https://api.telegram.org/bot%s/sendPhoto' % BOT_TOKEN, data=body,
        headers={'Content-Type': 'multipart/form-data; boundary=' + b})
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.load(r).get('ok') is True


class Handler(BaseHTTPRequestHandler):
    timeout = 30

    def handle(self):
        try:
            super().handle()
        except (ssl.SSLError, OSError):
            pass

    def cors(self):
        # The page lives on the same host (different port), so allow only that host.
        origin = self.headers.get('Origin', '')
        host = (self.headers.get('Host') or '').split(':')[0]
        if origin and urllib.parse.urlparse(origin).hostname == host:
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Vary', 'Origin')

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Sub-Path, X-Username, X-Note')
        self.send_header('Access-Control-Max-Age', '86400')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def reply(self, code, ok, error=''):
        body = json.dumps({'ok': ok, 'error': error}, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.cors()
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.split('?')[0] != '/receipt-upload':
            return self.reply(404, False, 'not found')
        ip = self.client_address[0]
        if over('ip:' + ip, IP_LIMIT_PER_HOUR, 3600):
            return self.reply(429, False, 'تعداد درخواست‌ها بیش از حد مجاز است. بعداً دوباره تلاش کنید.')
        record('ip:' + ip)
        try:
            size = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            size = 0
        if size <= 0 or size > MAX_BYTES:
            return self.reply(413, False, 'حجم تصویر مجاز نیست.')
        data = self.rfile.read(size)
        kind = sniff(data)
        if not kind:
            return self.reply(415, False, 'فقط تصویر JPG، PNG یا WEBP مجاز است.')

        note = urllib.parse.unquote(self.headers.get('X-Note', ''))
        note = re.sub(r'[\x00-\x08\x0b-\x1f\x7f]', '', note)[:300].strip()
        fallback = urllib.parse.unquote(self.headers.get('X-Username', ''))
        fallback = re.sub(r'[^\w.\-@ ]', '', fallback)[:64].strip()
        name = get_username(self.headers.get('X-Sub-Path', ''), fallback)
        if not name:
            return self.reply(403, False, 'اشتراک نامعتبر است.')
        if over('user:' + name, USER_LIMIT, USER_WINDOW):
            return self.reply(429, False, 'سقف ارسال فیش (%d فیش در %d ساعت) تکمیل شده است. بعداً دوباره تلاش کنید.' % (USER_LIMIT, USER_WINDOW // 3600))

        try:
            caption = '🧾 فیش واریزی\n👤 نام کاربری: %s' % name
            if note:
                caption += '\n📝 توضیحات: %s' % note
            ok = send_photo(data, kind[0], kind[1], caption)
        except Exception as e:
            print('telegram error:', type(e).__name__, getattr(e, 'code', ''), file=sys.stderr)
            ok = False
        if not ok:
            return self.reply(502, False, 'ارسال به تلگرام ناموفق بود. دوباره تلاش کنید.')
        record('user:' + name)
        self.reply(200, True)

    def log_message(self, fmt, *args):
        pass


if __name__ == '__main__':
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    if SSL_CERT:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(SSL_CERT, SSL_KEY or None)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True, do_handshake_on_connect=False)
    if os.getuid() == 0 and DROP_USER:  # certificate is loaded; run unprivileged from here on
        pw = pwd.getpwnam(DROP_USER)
        os.setgroups([])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)
    print('receipt relay on %s:%d (%s)' % (HOST, PORT, 'https' if SSL_CERT else 'http'))
    srv.serve_forever()
PYEOF
  chmod 644 "$APP_DIR/receipt.py"
}

write_service() {
  cat > "$UNIT" <<EOF
[Unit]
Description=Receipt relay (online renewal)
After=network.target

[Service]
ExecStart=$(command -v python3) $APP_DIR/receipt.py
Restart=always
RestartSec=3
RuntimeMaxSec=604800
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

fix_perms() {
  id receipt >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin receipt
  chown -R receipt:receipt "$APP_DIR"
  chmod 700 "$APP_DIR"
  [ -f "$CONF" ] && chmod 600 "$CONF"
  return 0
}

env_get() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$PANEL_ENV" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d " \"'\r" || true; }

detect_panel_url() {
  local port scheme=http
  port="$(env_get UVICORN_PORT)"
  [ -n "$(env_get UVICORN_SSL_CERTFILE)" ] && scheme=https
  echo "$scheme://127.0.0.1:${port:-8000}"
}

set_conf() {
  if grep -qE "^$1=" "$CONF"; then sed -i "s|^$1=.*|$1=$2|" "$CONF"; else echo "$1=$2" >> "$CONF"; fi
}

migrate_conf() {
  if ! grep -q '^CONF_VERSION=2' "$CONF"; then
    set_conf CONF_VERSION 2
    set_conf HOST 0.0.0.0
    set_conf PORT "$PORT"
    set_conf PANEL_URL "$(detect_panel_url)"
    set_conf SSL_CERT "$(env_get UVICORN_SSL_CERTFILE)"
    set_conf SSL_KEY "$(env_get UVICORN_SSL_KEYFILE)"
  fi
}

check_cert() {
  local cert; cert="$(grep '^SSL_CERT=' "$CONF" | cut -d= -f2-)"
  if [ -z "$cert" ]; then
    warn "No SSL certificate found in $PANEL_ENV. Set SSL_CERT and SSL_KEY in $CONF (same files your panel uses), then restart: systemctl restart $SERVICE"
  elif [ ! -r "$cert" ]; then
    warn "Certificate file not readable on this server: $cert. Fix SSL_CERT/SSL_KEY in $CONF."
  fi
}

open_port() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$PORT/tcp" >/dev/null && say "Firewall: opened TCP $PORT (ufw)"
  else
    warn "If a firewall (server or hosting provider) is active, open TCP port $PORT."
  fi
}

close_port() {
  if command -v ufw >/dev/null 2>&1; then ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true; fi
}

health() {
  sleep 1
  systemctl is-active --quiet "$SERVICE" || { warn "Service failed to start: journalctl -u $SERVICE -n 30"; return 0; }
  local code; code="$(curl -sk -m 5 -o /dev/null -w '%{http_code}' -X POST "https://127.0.0.1:$PORT/receipt-upload" || true)"
  if [ "$code" = "413" ]; then say "Relay is running on HTTPS port $PORT"; else warn "Relay did not answer as expected on port $PORT (got '$code'). Check: journalctl -u $SERVICE -n 30"; fi
}

do_install() {
  say "First-time install"
  local token chat a
  while :; do
    ask "Telegram bot API token: " token
    [ -n "$token" ] || continue
    if curl -fsS -m 15 "https://api.telegram.org/bot${token}/getMe" 2>/dev/null | grep -q '"ok":true'; then break; fi
    warn "Telegram rejected this token (or api.telegram.org is unreachable from this server)."
    ask "Use it anyway? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] && break
  done
  while :; do
    ask "Chat ID (numeric): " chat
    [[ "$chat" =~ ^-?[0-9]+$ ]] && break
    warn "Chat ID must be a number."
  done

  write_relay
  ( umask 177; cat > "$CONF" <<EOF
BOT_TOKEN=$token
CHAT_ID=$chat
CONF_VERSION=2
PANEL_URL=$(detect_panel_url)
HOST=0.0.0.0
PORT=$PORT
SSL_CERT=$(env_get UVICORN_SSL_CERTFILE)
SSL_KEY=$(env_get UVICORN_SSL_KEYFILE)
MAX_MB=8
USER_LIMIT=3
USER_WINDOW_HOURS=12
IP_LIMIT_PER_HOUR=30
EOF
  )
  fix_perms
  check_cert
  write_service
  systemctl enable --now "$SERVICE" >/dev/null 2>&1
  open_port
  health
  if curl -fsS -m 15 -o /dev/null --data-urlencode "chat_id=$chat" --data-urlencode "text=✅ Receipt relay is connected" "https://api.telegram.org/bot${token}/sendMessage" 2>/dev/null; then
    say "Test message sent to your bot"
  else
    warn "Could not send a test message. Check the Chat ID and press Start on your bot first."
  fi
  say "Done. Put the new index.html in your subscription template folder."
}

do_update() {
  [ -f "$CONF" ] || die "Config not found: $CONF"
  say "Updating (token and chat ID are kept)"
  write_relay
  migrate_conf
  sed -i '/^RATE_PER_HOUR=/d' "$CONF"
  fix_perms
  check_cert
  write_service
  open_port
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE"
  health
}

do_uninstall() {
  local a; ask "Remove receipt relay completely (service, files, token)? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || { say "Cancelled"; exit 0; }
  systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
  rm -f "$UNIT"; systemctl daemon-reload
  close_port
  rm -rf "$APP_DIR"
  userdel receipt >/dev/null 2>&1 || true
  say "Uninstalled. Your subscription template (index.html) was not touched."
}

action="${1:-}"
if [ -f "$CONF" ] && [ -f "$UNIT" ]; then
  if [ -z "$action" ]; then
    echo "Receipt relay is already installed. Choose:"
    echo "  1) update"
    echo "  2) uninstall"
    echo "  0) exit"
    ask "> " action
  fi
  case "$action" in
    1|update) do_update ;;
    2|uninstall) do_uninstall ;;
    *) exit 0 ;;
  esac
else
  do_install
fi
