#!/usr/bin/env bash

UFW_AVAILABLE=0
UFW_ACTIVE=0

ufw_detect() {
  UFW_AVAILABLE=0
  UFW_ACTIVE=0
  command -v ufw >/dev/null 2>&1 || return 0
  UFW_AVAILABLE=1
  if ufw status 2>/dev/null | grep -qi 'Status: active'; then
    UFW_ACTIVE=1
  fi
}

ufw_port_allowed() {
  local port="$1"
  [[ "$UFW_ACTIVE" == "1" ]] || return 1
  ufw status 2>/dev/null | grep -qE "(^|[[:space:]])${port}/tcp[[:space:]]+ALLOW"
}

ufw_show_status_hint() {
  if [[ "$UFW_AVAILABLE" != "1" ]]; then
    ui_info "UFW не установлен — проверьте iptables/nftables вручную при проблемах с доступом"
    return 0
  fi
  if [[ "$UFW_ACTIVE" != "1" ]]; then
    ui_info "UFW установлен, но не активен"
    return 0
  fi
  ui_info "UFW активен"
}

ufw_interactive_allow() {
  local port="$1"
  ufw_detect

  if [[ "$UFW_ACTIVE" != "1" ]]; then
    ufw_show_status_hint
    return 0
  fi

  if ufw_port_allowed "$port"; then
    ui_success "Порт ${port}/tcp уже разрешён в UFW"
    return 0
  fi

  ui_warn "Порт ${port}/tcp не открыт в UFW — клиенты Telegram не смогут подключиться"

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    if [[ "${UFW_ALLOW:-0}" == "1" ]]; then
      ufw_allow_port "$port"
    else
      ui_warn "Non-interactive: UFW не изменён (используйте --ufw-allow)"
    fi
    return 0
  fi

  local action
  action=$(ui_choose "Открыть порт ${port}/tcp в UFW?" \
    "Да, открыть сейчас" \
    "Показать команду" \
    "Нет, сделаю сам") || return 0

  case "$action" in
    "Да, открыть сейчас")
      ufw_allow_port "$port"
      ;;
    "Показать команду")
      echo ""
      echo "  sudo ufw allow ${port}/tcp comment 'tg-mtproto'"
      echo ""
      ui_confirm "Выполнили команду?" false || ui_warn "Не забудьте открыть порт ${port}/tcp"
      ;;
    *)
      ui_warn "Порт ${port}/tcp не открыт — подключение снаружи может не работать"
      ;;
  esac
}

ufw_allow_port() {
  local port="$1"
  local cmd=(ufw allow "${port}/tcp" comment 'tg-mtproto')

  if [[ "$EUID" -eq 0 ]]; then
    "${cmd[@]}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "${cmd[@]}"
  else
    ui_error "Нужны права root/sudo для ufw allow"
    echo "  sudo ufw allow ${port}/tcp comment 'tg-mtproto'"
    return 1
  fi

  if ufw_port_allowed "$port"; then
    ui_success "UFW: разрешён ${port}/tcp"
  else
    ui_warn "Команда выполнена, но правило не найдено — проверьте: sudo ufw status"
  fi
}
