#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/.env" ]]; then
  echo "Файл .env не найден. Сначала запустите ./init.sh" >&2
  exit 1
fi

echo "=== Docker Compose status ==="
docker compose ps
echo ""

if docker compose ps --status running --services 2>/dev/null | grep -qx mtg; then
  echo "=== mtg doctor ==="
  docker compose exec -T mtg /mtg doctor /config.toml || true
else
  echo "[!] Контейнер mtg не запущен"
  echo "    Запуск: docker compose up -d"
  exit 1
fi

echo ""
echo "=== Health ==="
docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
