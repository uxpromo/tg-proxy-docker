#!/usr/bin/env bash

MTG_IMAGE="${MTG_IMAGE:-nineseconds/mtg:2.2}"

secrets_generate_simple() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    docker run --rm "$MTG_IMAGE" generate-secret --hex 2>/dev/null | tail -1 || {
      ui_error "Не удалось сгенерировать секрет (нужен openssl или docker)"
      return 1
    }
  fi
}

secrets_generate_faketls() {
  local domain="$1"
  docker run --rm "$MTG_IMAGE" generate-secret --hex "$domain" 2>/dev/null | tail -1
}

secrets_generate() {
  local mode="$1"
  local domain="$2"
  local secret=""

  case "$mode" in
    simple)
      secret=$(secrets_generate_simple) || return 1
      ;;
    faketls)
      secret=$(secrets_generate_faketls "$domain") || return 1
      ;;
    *)
      ui_error "Неизвестный режим секрета: $mode"
      return 1
      ;;
  esac

  secret="$(echo "$secret" | tr -d '[:space:]')"
  if [[ -z "$secret" ]]; then
    ui_error "Пустой секрет"
    return 1
  fi
  GENERATED_SECRET="$secret"
}
