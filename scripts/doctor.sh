#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/.env" ]]; then
  echo "Файл .env не найден. Сначала запустите ./init.sh" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ROOT/.env"

profiles=""
if [[ "${SOCKS5_ENABLED:-0}" == "1" ]]; then
  profiles="--profile bot"
fi

echo "=== Docker Compose status ==="
# shellcheck disable=SC2086
docker compose $profiles ps
echo ""

if docker compose ps --status running --services 2>/dev/null | grep -qx mtg; then
  echo "=== mtg doctor ==="
  docker compose exec -T mtg /mtg doctor /config.toml || true
else
  echo "[!] Контейнер mtg не запущен"
  echo "    Запуск: docker compose $profiles up -d"
  exit 1
fi

if [[ "${SOCKS5_ENABLED:-0}" == "1" ]]; then
  echo ""
  echo "=== SOCKS5 (bot) ==="
  if docker compose $profiles ps --status running --services 2>/dev/null | grep -qx socks5; then
    echo "[ok] Контейнер socks5 запущен на порту ${SOCKS5_HOST_PORT:-1080}"
    echo "    Подробности: ./scripts/show-bot-proxy.sh"
  else
    echo "[!] SOCKS5 включён в .env, но контейнер не запущен"
    echo "    Запуск: docker compose --profile bot up -d"
  fi
fi

echo ""
echo "=== Health ==="
# shellcheck disable=SC2086
docker compose $profiles ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
