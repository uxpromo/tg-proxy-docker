#!/usr/bin/env bash

PORT_CANDIDATES=(443 80 8443 4433 2053 2083 3128 10000 10443)

ports_listening() {
  ss -tlnH 2>/dev/null | awk '{print $4}' | sed -E 's/.*://' | sort -u
}

ports_is_listening() {
  local port="$1"
  ss -tlnH 2>/dev/null | awk -v p=":$port" '{print $4}' | grep -qE ":${port}$"
}

ports_get_listener_hint() {
  local port="$1"
  local line proc
  line=$(ss -tlnpH 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {print; exit}')
  if [[ -z "$line" ]]; then
    echo "—"
    return 0
  fi
  if [[ "$line" =~ users:\(\(\"([^\"]+)\" ]]; then
    proc="${BASH_REMATCH[1]}"
    echo "$proc"
  else
    echo "занят"
  fi
}

ports_can_bind() {
  local port="$1"
  if ports_is_listening "$port"; then
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("0.0.0.0", port))
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
    return $?
  fi
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && return 1
    return 0
  fi
  return 0
}

ports_recommendation() {
  local port="$1"
  if ports_is_listening "$port"; then
    echo "занят"
    return 0
  fi
  if ! ports_can_bind "$port"; then
    echo "недоступен"
    return 0
  fi
  case "$port" in
    8443|4433|10443) echo "★ рекомендуем" ;;
    443|80) echo "стандартный (часто занят)" ;;
    *) echo "свободен" ;;
  esac
}

ports_build_table_rows() {
  PORT_TABLE_ROWS=()
  local port listener rec ufw_col
  for port in "${PORT_CANDIDATES[@]}"; do
    listener=$(ports_get_listener_hint "$port")
    rec=$(ports_recommendation "$port")
    if [[ "${UFW_ACTIVE:-0}" == "1" ]]; then
      if ufw_port_allowed "$port"; then
        ufw_col="ALLOW"
      else
        ufw_col="DENY/нет правила"
      fi
      PORT_TABLE_ROWS+=("${port}|${listener}|${ufw_col}|${rec}")
    else
      PORT_TABLE_ROWS+=("${port}|${listener}|${rec}")
    fi
  done
}

ports_pick_default() {
  local port rec
  for port in 8443 4433 10443 2053 2083 10000; do
    if ! ports_is_listening "$port" && ports_can_bind "$port"; then
      echo "$port"
      return 0
    fi
  done
  for port in "${PORT_CANDIDATES[@]}"; do
    if ! ports_is_listening "$port" && ports_can_bind "$port"; then
      echo "$port"
      return 0
    fi
  done
  echo "8443"
}

ports_validate_choice() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    ui_error "Некорректный порт: $port"
    return 1
  fi
  if ports_is_listening "$port"; then
    ui_error "Порт $port уже занят ($(ports_get_listener_hint "$port"))"
    return 1
  fi
  if ! ports_can_bind "$port"; then
    ui_error "Не удалось зарезервировать порт $port"
    return 1
  fi
  return 0
}

ports_interactive_select() {
  ports_build_table_rows

  if [[ "${UFW_ACTIVE:-0}" == "1" ]]; then
    ui_table "Порт" "Слушает" "UFW" "Рекомендация" -- "${PORT_TABLE_ROWS[@]}"
  else
    ui_table "Порт" "Слушает" "Рекомендация" -- "${PORT_TABLE_ROWS[@]}"
  fi

  echo ""
  local default free_options=()
  default=$(ports_pick_default)
  local port rec listener
  for port in "${PORT_CANDIDATES[@]}"; do
    rec=$(ports_recommendation "$port")
    listener=$(ports_get_listener_hint "$port")
    if [[ "$rec" != "занят" && "$rec" != "недоступен" ]]; then
      free_options+=("$port — $rec ($listener)")
    fi
  done
  free_options+=("Другой порт (ввести вручную)")

  local choice
  choice=$(ui_filter "Выберите порт для MTProto proxy" "${free_options[@]}") || return 1

  if [[ "$choice" == "Другой порт (ввести вручную)" ]]; then
    choice=$(ui_input "Введите TCP-порт" "$default" "8443")
  else
    choice="${choice%% —*}"
  fi

  choice="$(echo "$choice" | tr -d '[:space:]')"
  ports_validate_choice "$choice" || return 1
  SELECTED_PORT="$choice"
}
