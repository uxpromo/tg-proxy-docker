#!/usr/bin/env bash

dns_detect_public_ip() {
  local ip=""
  for url in "https://api4.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    if command -v curl >/dev/null 2>&1; then
      ip=$(curl -4fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
    elif command -v wget >/dev/null 2>&1; then
      ip=$(wget -qO- --timeout=5 "$url" 2>/dev/null | tr -d '[:space:]')
    fi
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    ip=""
  done

  if [[ -z "$ip" ]]; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
  fi

  DETECTED_PUBLIC_IP="$ip"
}

dns_resolve_a() {
  local domain="$1"
  local result=""

  if command -v dig >/dev/null 2>&1; then
    result=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
  elif command -v getent >/dev/null 2>&1; then
    result=$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}')
  elif command -v host >/dev/null 2>&1; then
    result=$(host -t A "$domain" 2>/dev/null | awk '/has address/ {print $4; exit}')
  fi

  DNS_A_RECORD="$result"
}

dns_validate_domain() {
  local domain="$1"
  domain="$(echo "$domain" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\.$//')"
  if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]; then
    ui_error "Некорректное имя домена: $domain"
    return 1
  fi
  VALIDATED_DOMAIN="$domain"
}

dns_check_domain_points_here() {
  local domain="$1"
  local server_ip="$2"

  dns_resolve_a "$domain"
  if [[ -z "$DNS_A_RECORD" ]]; then
    ui_warn "Не удалось получить A-record для $domain"
    return 1
  fi

  if [[ "$DNS_A_RECORD" != "$server_ip" ]]; then
    ui_warn "DNS: $domain → $DNS_A_RECORD, IP сервера: ${server_ip:-не определён}"
    ui_warn "Telegram может не подключиться, пока DNS не укажет на этот сервер"
    return 1
  fi

  ui_success "DNS OK: $domain → $DNS_A_RECORD"
  return 0
}

dns_interactive_domain() {
  dns_detect_public_ip
  local use_domain=false
  local domain=""

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    if [[ -n "${CLI_DOMAIN:-}" ]]; then
      use_domain=true
      domain="$CLI_DOMAIN"
    else
      SELECTED_MODE="simple"
      SELECTED_SERVER="${DETECTED_PUBLIC_IP:-127.0.0.1}"
      SELECTED_DOMAIN=""
      return 0
    fi
  else
    if ui_confirm "Есть домен, указывающий на этот сервер?" false; then
      use_domain=true
      domain=$(ui_input "Введите домен" "" "proxy.example.com")
    fi
  fi

  if [[ "$use_domain" != "true" ]]; then
    SELECTED_MODE="simple"
    SELECTED_DOMAIN=""
    SELECTED_SERVER="${DETECTED_PUBLIC_IP:-127.0.0.1}"
    if [[ -z "$DETECTED_PUBLIC_IP" ]]; then
      SELECTED_SERVER=$(ui_input "Публичный IP сервера" "" "1.2.3.4")
    else
      ui_info "Публичный IP: $DETECTED_PUBLIC_IP"
    fi
    return 0
  fi

  dns_validate_domain "$domain" || return 1
  domain="$VALIDATED_DOMAIN"

  if [[ "${NONINTERACTIVE:-0}" != "1" ]]; then
    dns_check_domain_points_here "$domain" "$DETECTED_PUBLIC_IP" || \
      ui_confirm "Продолжить несмотря на несовпадение DNS?" true || return 1
  fi

  SELECTED_MODE="faketls"
  SELECTED_DOMAIN="$domain"
  SELECTED_SERVER="$domain"
}
