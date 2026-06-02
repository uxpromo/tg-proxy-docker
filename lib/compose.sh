#!/usr/bin/env bash

compose_build_links() {
  local server="$1"
  local port="$2"
  local secret="$3"
  local enc_server
  enc_server=$(python3 - "$server" <<'PY' 2>/dev/null || echo "$server"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)
  LINK_TG="tg://proxy?server=${enc_server}&port=${port}&secret=${secret}"
  LINK_HTTPS="https://t.me/proxy?server=${enc_server}&port=${port}&secret=${secret}"
}

compose_write_mtg_toml() {
  local secret="$1"
  local bind_port="$2"
  local listen_host="${3:-0.0.0.0}"
  local config_dir="$PROJECT_ROOT/config"
  mkdir -p "$config_dir"
  cat >"$config_dir/mtg.toml" <<EOF
secret = "${secret}"
bind-to = "${listen_host}:${bind_port}"
EOF
}

compose_write_env() {
  local docker_host_port="$1"
  local bind_port="$2"
  local secret="$3"
  local domain="$4"
  local server="$5"
  local mode="$6"
  local client_port="$7"
  local tz="${8:-UTC}"
  local publish_host="${9:-0.0.0.0}"

  compose_build_links "$server" "$client_port" "$secret"

  cat >"$PROJECT_ROOT/.env" <<EOF
MTPROTO_HOST_PORT=${docker_host_port}
MTPROTO_CLIENT_PORT=${client_port}
MTPROTO_BIND_PORT=${bind_port}
MTPROTO_PUBLISH_HOST=${publish_host}
MTPROTO_SECRET=${secret}
MTPROTO_DOMAIN=${domain}
MTPROTO_SERVER=${server}
MTPROTO_MODE=${mode}
MTPROTO_LINK_TG=${LINK_TG}
MTPROTO_LINK_HTTPS=${LINK_HTTPS}
TZ=${tz}
EOF
}

compose_show_final_summary() {
  ui_title "Готово"
  echo ""
  echo "  Server:  ${SELECTED_SERVER}"
  echo "  Port:    ${CLIENT_PORT:-$SELECTED_PORT}"
  echo "  Mode:    ${SELECTED_MODE}"
  echo "  Secret:  ${GENERATED_SECRET}"
  echo ""
  echo "  Telegram:"
  echo "  ${LINK_TG}"
  echo ""
  echo "  Share:"
  echo "  ${LINK_HTTPS}"
  echo ""
  ui_info "Повторно показать ссылку: ./scripts/show-link.sh"
  ui_info "Диагностика: ./scripts/doctor.sh"
}

compose_start_stack() {
  ui_spin "Запуск docker compose" bash -c "
    set -euo pipefail
    cd \"$PROJECT_ROOT\"
    docker compose up -d
  " || {
    ui_error "Не удалось запустить контейнер"
    return 1
  }

  ui_spin "Проверка mtg doctor" bash -c "
    set -euo pipefail
    cd \"$PROJECT_ROOT\"
    sleep 2
    docker compose exec -T mtg /mtg doctor /config.toml
  " || ui_warn "mtg doctor сообщил о проблемах — см. ./scripts/doctor.sh"
}

compose_show_reverse_proxy_snippet() {
  local choice="$1"
  local snippet=""
  local file=""

  case "$choice" in
    "Caddy L4")
      file="$PROJECT_ROOT/reverse-proxy/caddy/layer4.caddyfile.example"
      ;;
    "nginx stream")
      file="$PROJECT_ROOT/reverse-proxy/nginx/stream.conf.example"
      ;;
    *)
      return 0
      ;;
  esac

  [[ -f "$file" ]] || {
    ui_warn "Сниппет не найден: $file"
    return 0
  }

  snippet=$(sed \
    -e "s/\${MTPROTO_DOMAIN}/${SELECTED_DOMAIN:-proxy.example.com}/g" \
    -e "s/\${MTPROTO_BIND_PORT}/${MTPROTO_BIND_PORT:-3128}/g" \
    -e "s/\${MTPROTO_HOST_PORT}/${SELECTED_PORT}/g" \
    "$file")

  ui_warn "Vanilla Caddy 2.x требует caddy-l4 для TCP/SNI routing"
  ui_pager "$snippet"
}
