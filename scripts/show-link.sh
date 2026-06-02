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

if command -v xclip >/dev/null 2>&1 && [[ -n "${MTPROTO_LINK_TG:-}" ]]; then
  echo "$MTPROTO_LINK_TG" | xclip -selection clipboard 2>/dev/null && echo "[ok] Ссылка tg:// скопирована в clipboard (xclip)"
elif command -v wl-copy >/dev/null 2>&1 && [[ -n "${MTPROTO_LINK_TG:-}" ]]; then
  echo "$MTPROTO_LINK_TG" | wl-copy 2>/dev/null && echo "[ok] Ссылка tg:// скопирована в clipboard (wl-copy)"
fi
