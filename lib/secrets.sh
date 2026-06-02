#!/usr/bin/env bash

MTG_IMAGE="${MTG_IMAGE:-nineseconds/mtg:2.2}"
# mtg v2 requires FakeTLS secrets (ee… hex or base64). Used when user has no own domain.
DEFAULT_FRONT_DOMAIN="${DEFAULT_FRONT_DOMAIN:-cloudflare.com}"

secrets_generate_faketls() {
  local domain="$1"
  local secret
  secret=$(docker run --rm "$MTG_IMAGE" generate-secret --hex "$domain" 2>/dev/null | tail -1 | tr -d '[:space:]')
  if [[ -z "$secret" ]]; then
    ui_error "Не удалось сгенерировать секрет для домена $domain"
    return 1
  fi
  echo "$secret"
}

secrets_generate_simple() {
  # No user domain: client connects by IP, secret still uses FakeTLS with a generic front domain.
  secrets_generate_faketls "$DEFAULT_FRONT_DOMAIN"
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

  GENERATED_SECRET="$secret"
}
