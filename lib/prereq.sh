#!/usr/bin/env bash

prereq_check_docker() {
  command -v docker >/dev/null 2>&1 || {
    ui_error "Docker не найден. Установите Docker: https://docs.docker.com/engine/install/"
    return 1
  }

  docker compose version >/dev/null 2>&1 || {
    ui_error "Docker Compose v2 не найден (команда: docker compose)"
    return 1
  }

  docker info >/dev/null 2>&1 || {
    ui_error "Docker daemon недоступен. Запустите docker и проверьте права пользователя"
    return 1
  }

  ui_success "Docker и Compose доступны"
}

prereq_setup_ui() {
  ui_detect
  if [[ "$UI_BACKEND" == "plain" ]]; then
    ui_offer_gum_install || true
    ui_detect
  fi
  ui_info "UI: $UI_BACKEND"
}

prereq_check_existing_config() {
  [[ -f "$PROJECT_ROOT/.env" && -f "$PROJECT_ROOT/config/mtg.toml" ]] || return 0

  ui_warn "Найдена существующая конфигурация (.env, config/mtg.toml)"
  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    ui_info "Non-interactive: конфигурация будет перезаписана"
    return 0
  fi
  ui_confirm "Перезаписать конфигурацию?" false || {
    ui_info "Отмена. Используйте docker compose up -d или ./scripts/show-link.sh"
    exit 0
  }
}
