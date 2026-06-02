#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

NONINTERACTIVE=0
CLI_YES=0
CLI_PORT=""
CLI_DOMAIN=""
CLI_NO_DOMAIN=0
UFW_ALLOW=0
CLI_START=1

MTPROTO_BIND_PORT=3128
SELECTED_PORT=""
SELECTED_MODE="simple"
SELECTED_DOMAIN=""
SELECTED_SERVER=""
GENERATED_SECRET=""
REVERSE_PROXY="none"
PUBLISH_HOST="0.0.0.0"
CLIENT_PORT=""

usage() {
  cat <<EOF
Usage: ./init.sh [options]

Interactive wizard for Telegram MTProto proxy (mtg + Docker Compose).

Options:
  -y, --yes              Non-interactive mode (use with --port)
  --port PORT            TCP port for clients (or internal port for SNI mode)
  --domain DOMAIN        Enable fake TLS mode with domain
  --no-domain            Simple mode (IP + hex secret)
  --ufw-allow            Open selected port in UFW (non-interactive)
  --no-start             Generate config only, do not run docker compose
  -h, --help             Show this help

Examples:
  ./init.sh
  ./init.sh --yes --port 8443 --no-domain
  ./init.sh --yes --port 443 --domain proxy.example.com --ufw-allow
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        NONINTERACTIVE=1
        CLI_YES=1
        shift
        ;;
      --port)
        CLI_PORT="$2"
        shift 2
        ;;
      --domain)
        CLI_DOMAIN="$2"
        shift 2
        ;;
      --no-domain)
        CLI_NO_DOMAIN=1
        shift
        ;;
      --ufw-allow)
        UFW_ALLOW=1
        shift
        ;;
      --no-start)
        CLI_START=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  if [[ "$NONINTERACTIVE" == "1" && -z "$CLI_PORT" ]]; then
    echo "Non-interactive mode requires --port" >&2
    exit 1
  fi
  if [[ -n "$CLI_DOMAIN" && "$CLI_NO_DOMAIN" == "1" ]]; then
    echo "Use either --domain or --no-domain" >&2
    exit 1
  fi
}

source_lib() {
  # shellcheck source=lib/ui.sh
  source "$PROJECT_ROOT/lib/ui.sh"
  # shellcheck source=lib/firewall.sh
  source "$PROJECT_ROOT/lib/firewall.sh"
  # shellcheck source=lib/ports.sh
  source "$PROJECT_ROOT/lib/ports.sh"
  # shellcheck source=lib/dns.sh
  source "$PROJECT_ROOT/lib/dns.sh"
  # shellcheck source=lib/secrets.sh
  source "$PROJECT_ROOT/lib/secrets.sh"
  # shellcheck source=lib/compose.sh
  source "$PROJECT_ROOT/lib/compose.sh"
  # shellcheck source=lib/prereq.sh
  source "$PROJECT_ROOT/lib/prereq.sh"
}

step_environment() {
  ui_step 1 7 "Окружение"
  prereq_setup_ui
  prereq_check_docker || exit 1
  prereq_check_existing_config
}

step_ports() {
  ui_step 2 7 "Порты"
  ufw_detect

  if [[ -n "$CLI_PORT" ]]; then
    SELECTED_PORT="$CLI_PORT"
    ports_validate_choice "$SELECTED_PORT" || exit 1
    ui_info "Порт: $SELECTED_PORT"
    return 0
  fi

  ports_interactive_select || exit 1
  ui_success "Выбран порт: $SELECTED_PORT"
}

step_domain() {
  ui_step 3 7 "Домен и режим"

  if [[ "$CLI_NO_DOMAIN" == "1" ]]; then
    dns_detect_public_ip
    SELECTED_MODE="simple"
    SELECTED_DOMAIN=""
    SELECTED_SERVER="${DETECTED_PUBLIC_IP:-127.0.0.1}"
    ui_info "Режим: simple (без домена)"
    return 0
  fi

  if [[ -n "$CLI_DOMAIN" ]]; then
    dns_detect_public_ip
    dns_validate_domain "$CLI_DOMAIN" || exit 1
    SELECTED_MODE="faketls"
    SELECTED_DOMAIN="$VALIDATED_DOMAIN"
    SELECTED_SERVER="$VALIDATED_DOMAIN"
    dns_check_domain_points_here "$SELECTED_DOMAIN" "$DETECTED_PUBLIC_IP" || true
    ui_info "Режим: faketls ($SELECTED_DOMAIN)"
    return 0
  fi

  dns_interactive_domain || exit 1
  ui_success "Режим: $SELECTED_MODE, server: $SELECTED_SERVER"
}

step_firewall() {
  ui_step 5 7 "UFW"
  local fw_port="${CLIENT_PORT:-$SELECTED_PORT}"
  ufw_interactive_allow "$fw_port"
}

step_reverse_proxy() {
  ui_step 4 7 "Reverse proxy (опционально)"

  if [[ "$NONINTERACTIVE" == "1" ]]; then
    return 0
  fi

  if ! ports_is_listening 443; then
    ui_info "Порт 443 свободен — SNI-routing обычно не нужен"
    if ! ui_confirm "Показать сниппеты Caddy/nginx anyway?" false; then
      return 0
    fi
  else
    ui_info "Порт 443 занят ($(ports_get_listener_hint 443)) — SNI-routing может понадобиться"
  fi

  local choice
  choice=$(ui_choose "Интеграция с reverse proxy на :443" \
    "Пропустить" \
    "Caddy L4" \
    "nginx stream") || return 0

  case "$choice" in
    "Caddy L4"|"nginx stream")
      REVERSE_PROXY="$choice"
      PUBLISH_HOST="127.0.0.1"
      CLIENT_PORT=443
      if [[ "$SELECTED_MODE" != "faketls" ]]; then
        ui_warn "SNI-routing лучше работает с доменом (fake TLS)"
      fi
      if [[ "$SELECTED_MODE" == "faketls" && -n "$SELECTED_DOMAIN" ]]; then
        ui_info "Клиенты подключаются: ${SELECTED_SERVER}:443"
      else
        CLIENT_PORT=$(ui_input "Порт для клиентов Telegram" "443" "443")
      fi
      ui_warn "mtg будет слушать только 127.0.0.1:${MTPROTO_BIND_PORT}"
      ui_warn "Настройте Caddy/nginx по сниппету из reverse-proxy/"
      compose_show_reverse_proxy_snippet "$choice"
      ;;
    *)
      REVERSE_PROXY="none"
      ;;
  esac
}

step_generate() {
  ui_step 6 7 "Генерация конфигурации"

  secrets_generate "$SELECTED_MODE" "$SELECTED_DOMAIN" || exit 1

  local listen_host="0.0.0.0"
  local docker_host_port="$SELECTED_PORT"
  local client_port="${CLIENT_PORT:-$SELECTED_PORT}"

  if [[ "$REVERSE_PROXY" != "none" ]]; then
    listen_host="127.0.0.1"
    docker_host_port="$MTPROTO_BIND_PORT"
    PUBLISH_HOST="127.0.0.1"
    client_port="${CLIENT_PORT:-443}"
  fi

  compose_write_mtg_toml "$GENERATED_SECRET" "$MTPROTO_BIND_PORT" "$listen_host"
  compose_write_env \
    "$docker_host_port" \
    "$MTPROTO_BIND_PORT" \
    "$GENERATED_SECRET" \
    "${SELECTED_DOMAIN}" \
    "$SELECTED_SERVER" \
    "$SELECTED_MODE" \
    "$client_port" \
    "${TZ:-UTC}" \
    "$PUBLISH_HOST"

  ui_success "Записаны config/mtg.toml и .env"
}

step_start() {
  ui_step 7 7 "Запуск"

  if [[ "${NONINTERACTIVE:-0}" == "1" && "$CLI_START" == "0" ]]; then
    ui_info "Конфигурация создана (--no-start)"
    compose_show_final_summary
    return 0
  fi

  if [[ "${NONINTERACTIVE:-0}" != "1" ]]; then
    ui_confirm "Запустить docker compose сейчас?" true || {
      compose_show_final_summary
      ui_info "Запуск вручную: docker compose up -d"
      return 0
    }
  fi

  compose_start_stack || exit 1
  compose_show_final_summary
}

main() {
  parse_args "$@"
  source_lib

  ui_title "Telegram MTProto Proxy — мастер установки"
  ui_info "Проект: $PROJECT_ROOT"

  step_environment
  step_ports
  step_domain
  step_reverse_proxy
  step_firewall
  step_generate
  step_start
}

main "$@"
