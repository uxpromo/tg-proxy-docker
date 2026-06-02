#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Файл .env не найден. Сначала запустите ./init.sh" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

links_build_from_parts() {
  local server="$1"
  local port="$2"
  local secret="$3"
  local enc_server="$server"

  if command -v python3 >/dev/null 2>&1; then
    enc_server=$(python3 - "$server" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)
  fi

  MTPROTO_LINK_TG="tg://proxy?server=${enc_server}&port=${port}&secret=${secret}"
  MTPROTO_LINK_HTTPS="https://t.me/proxy?server=${enc_server}&port=${port}&secret=${secret}"
}

links_ensure() {
  if [[ -n "${MTPROTO_LINK_TG:-}" && -n "${MTPROTO_LINK_HTTPS:-}" ]]; then
    return 0
  fi

  local server port secret
  server="${MTPROTO_SERVER:-}"
  port="${MTPROTO_CLIENT_PORT:-${MTPROTO_HOST_PORT:-}}"
  secret="${MTPROTO_SECRET:-}"

  if [[ -z "$server" || -z "$port" || -z "$secret" ]]; then
    echo "В .env нет ссылок и не хватает MTPROTO_SERVER / PORT / SECRET. Запустите ./init.sh" >&2
    exit 1
  fi

  links_build_from_parts "$server" "$port" "$secret"
}

links_ensure

echo ""
echo "=== Telegram MTProto Proxy ==="
echo ""
echo "  Server: ${MTPROTO_SERVER:-?}"
echo "  Port:   ${MTPROTO_CLIENT_PORT:-${MTPROTO_HOST_PORT:-?}}"
echo "  Mode:   ${MTPROTO_MODE:-?}"
echo ""
echo "  tg://"
echo "  ${MTPROTO_LINK_TG#tg://}"
echo ""
echo "  https://"
echo "  ${MTPROTO_LINK_HTTPS#https://}"
echo ""

if command -v xclip >/dev/null 2>&1; then
  echo "$MTPROTO_LINK_TG" | xclip -selection clipboard 2>/dev/null && echo "[ok] Ссылка tg:// скопирована в clipboard (xclip)"
elif command -v wl-copy >/dev/null 2>&1; then
  echo "$MTPROTO_LINK_TG" | wl-copy 2>/dev/null && echo "[ok] Ссылка tg:// скопирована в clipboard (wl-copy)"
fi
