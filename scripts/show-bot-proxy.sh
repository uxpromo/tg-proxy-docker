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

if [[ "${SOCKS5_ENABLED:-0}" != "1" ]]; then
  echo "SOCKS5 для ботов не включён." >&2
  echo "Перезапустите ./init.sh и ответьте «Да» на «Поднять SOCKS5-прокси для Telegram Bot API?»" >&2
  echo "Или: ./init.sh --yes --port 4433 --domain example.com --bot-proxy --ufw-allow" >&2
  exit 1
fi

echo ""
echo "=== SOCKS5 для Telegram Bot API ==="
echo ""
echo "  Host:  ${MTPROTO_SERVER:-?}:${SOCKS5_HOST_PORT:-?}"
echo "  User:  ${SOCKS5_USER:-?}"
echo "  Pass:  ${SOCKS5_PASSWORD:-?}"
echo ""
echo "  --- .env на сервере бота ---"
echo ""
echo "  TELEGRAM_PROXY_URL='${BOT_PROXY_URL:-}'"
echo "  HTTPS_PROXY='${BOT_PROXY_URL:-}'"
echo "  HTTP_PROXY='${BOT_PROXY_URL:-}'"
echo ""
echo "  --- python-telegram-bot (пример) ---"
echo ""
echo "  from telegram.request import HTTPXRequest"
echo "  request = HTTPXRequest(proxy='${BOT_PROXY_URL:-}')"
echo "  application = Application.builder().token(TOKEN).request(request).build()"
echo ""
echo "  --- curl (проверка с сервера бота) ---"
echo ""
echo "  curl -x '${BOT_PROXY_URL:-}' --max-time 15 https://api.telegram.org"
echo ""
