#!/usr/bin/env bash

SOCKS5_ENABLED=0
SOCKS5_HOST_PORT=1080
SOCKS5_PUBLISH_HOST="0.0.0.0"
SOCKS5_USER=""
SOCKS5_PASSWORD=""
BOT_PROXY_URL=""

bot_proxy_generate_credentials() {
  SOCKS5_USER="${SOCKS5_USER:-tgproxy}"
  if [[ -z "$SOCKS5_PASSWORD" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      SOCKS5_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
    else
      SOCKS5_PASSWORD=$(date +%s | sha256sum | head -c 20)
    fi
  fi
}

bot_proxy_build_url() {
  local host="$1"
  local port="$2"
  local user="$3"
  local pass="$4"
  local enc_user enc_pass

  if command -v python3 >/dev/null 2>&1; then
    enc_user=$(python3 - "$user" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)
    enc_pass=$(python3 - "$pass" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)
  else
    enc_user="$user"
    enc_pass="$pass"
  fi

  BOT_PROXY_URL="socks5h://${enc_user}:${enc_pass}@${host}:${port}"
}

bot_proxy_validate_port() {
  local port="$1"
  if ports_is_listening "$port"; then
    ui_error "Порт $port занят ($(ports_get_listener_hint "$port"))"
    return 1
  fi
  if ! ports_can_bind "$port"; then
    ui_error "Порт $port недоступен для bind"
    return 1
  fi
  return 0
}

bot_proxy_pick_port() {
  local candidates=(1080 1081 10808 11080)
  local port
  for port in "${candidates[@]}"; do
    if ! ports_is_listening "$port" && ports_can_bind "$port"; then
      echo "$port"
      return 0
    fi
  done
  echo "1080"
}

bot_proxy_interactive_setup() {
  SOCKS5_ENABLED=0

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    [[ "${CLI_BOT_PROXY:-0}" == "1" ]] || return 0
    SOCKS5_ENABLED=1
    SOCKS5_HOST_PORT="${CLI_BOT_PORT:-$(bot_proxy_pick_port)}"
    bot_proxy_validate_port "$SOCKS5_HOST_PORT" || exit 1
    bot_proxy_generate_credentials
    return 0
  fi

  ui_info "SOCKS5 нужен ботам и скриптам на заблокированных серверах (не путать с tg:// для клиентов)"
  ui_confirm "Поднять SOCKS5-прокси для Telegram Bot API?" false || return 0

  SOCKS5_ENABLED=1
  local default_port
  default_port=$(bot_proxy_pick_port)

  if ports_is_listening "$default_port"; then
    ui_warn "Порт ${default_port} занят — укажите другой"
    default_port=$(ui_input "Порт SOCKS5 на хосте" "1081" "1080")
  else
    ui_info "Рекомендуемый порт SOCKS5: ${default_port}"
    if ! ui_confirm "Использовать порт ${default_port}?" true; then
      default_port=$(ui_input "Порт SOCKS5 на хосте" "$default_port" "1080")
    fi
  fi

  default_port="$(echo "$default_port" | tr -d '[:space:]')"
  bot_proxy_validate_port "$default_port" || return 1
  SOCKS5_HOST_PORT="$default_port"

  bot_proxy_generate_credentials
  ui_success "SOCKS5: порт ${SOCKS5_HOST_PORT}, пользователь ${SOCKS5_USER}"
}
