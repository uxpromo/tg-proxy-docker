#!/usr/bin/env bash
# UI abstraction: gum -> whiptail/dialog -> plain bash

UI_BACKEND="plain"

ui_detect() {
  if [[ -n "${TG_PROXY_UI:-}" ]]; then
    UI_BACKEND="$TG_PROXY_UI"
    return 0
  fi

  if command -v gum >/dev/null 2>&1; then
    UI_BACKEND="gum"
  elif command -v whiptail >/dev/null 2>&1; then
    UI_BACKEND="whiptail"
  elif command -v dialog >/dev/null 2>&1; then
    UI_BACKEND="dialog"
  else
    UI_BACKEND="plain"
  fi
}

ui_title() {
  local text="$1"
  case "$UI_BACKEND" in
    gum)
      gum style --border double --padding "0 2" --margin "1 0" "$text"
      ;;
    *)
      echo ""
      echo "=== $text ==="
      echo ""
      ;;
  esac
}

ui_info() {
  local text="$1"
  case "$UI_BACKEND" in
    gum)
      gum log --level info "$text"
      ;;
    *)
      echo "[i] $text"
      ;;
  esac
}

ui_warn() {
  local text="$1"
  case "$UI_BACKEND" in
    gum)
      gum log --level warn "$text"
      ;;
    *)
      echo "[!] $text" >&2
      ;;
  esac
}

ui_error() {
  local text="$1"
  case "$UI_BACKEND" in
    gum)
      gum log --level error "$text"
      ;;
    *)
      echo "[x] $text" >&2
      ;;
  esac
}

ui_success() {
  local text="$1"
  case "$UI_BACKEND" in
    gum)
      gum style --foreground 10 "$text"
      ;;
    *)
      echo "[ok] $text"
      ;;
  esac
}

ui_step() {
  local current="$1"
  local total="$2"
  local text="$3"
  ui_title "[$current/$total] $text"
}

ui_confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-true}"

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    [[ "$default" == "true" ]]
    return $?
  fi

  case "$UI_BACKEND" in
    gum)
      if [[ "$default" == "true" ]]; then
        gum confirm "$prompt"
      else
        gum confirm --default=false "$prompt"
      fi
      ;;
    whiptail|dialog)
      local cmd="$UI_BACKEND"
      if [[ "$default" == "true" ]]; then
        $cmd --yesno "$prompt" 10 70
      else
        $cmd --defaultno --yesno "$prompt" 10 70
      fi
      ;;
    *)
      local hint="Y/n"
      [[ "$default" == "false" ]] && hint="y/N"
      read -r -p "$prompt ($hint): " answer
      answer="${answer:-}"
      if [[ -z "$answer" ]]; then
        [[ "$default" == "true" ]]
        return $?
      fi
      case "${answer,,}" in
        y|yes|д|да) return 0 ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"
  local placeholder="${3:-}"

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    echo "$default"
    return 0
  fi

  case "$UI_BACKEND" in
    gum)
      local args=(input --prompt "$prompt " --width 60)
      [[ -n "$placeholder" ]] && args+=(--placeholder "$placeholder")
      [[ -n "$default" ]] && args+=(--value "$default")
      gum "${args[@]}"
      ;;
    whiptail|dialog)
      local cmd="$UI_BACKEND"
      $cmd --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3
      ;;
    *)
      local value="$default"
      read -r -p "$prompt${default:+ [$default]}: " value
      echo "${value:-$default}"
      ;;
  esac
}

ui_choose() {
  local prompt="$1"
  shift
  local options=("$@")

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    echo "${options[0]}"
    return 0
  fi

  case "$UI_BACKEND" in
    gum)
      gum choose --header "$prompt" "${options[@]}"
      ;;
    whiptail|dialog)
      local cmd="$UI_BACKEND"
      local menu_args=()
      local i=0
      for opt in "${options[@]}"; do
        menu_args+=("$i" "$opt")
        i=$((i + 1))
      done
      local choice
      choice=$($cmd --menu "$prompt" 20 78 10 "${menu_args[@]}" 3>&1 1>&2 2>&3) || return 1
      echo "${options[$choice]}"
      ;;
    *)
      echo "$prompt"
      local n=1
      for opt in "${options[@]}"; do
        echo "  $n) $opt"
        n=$((n + 1))
      done
      local pick
      read -r -p "Выбор [1]: " pick
      pick="${pick:-1}"
      echo "${options[$((pick - 1))]}"
      ;;
  esac
}

ui_filter() {
  local prompt="$1"
  shift
  local options=("$@")

  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    echo "${options[0]}"
    return 0
  fi

  case "$UI_BACKEND" in
    gum)
      printf '%s\n' "${options[@]}" | gum filter --placeholder "$prompt"
      ;;
    *)
      ui_choose "$prompt" "${options[@]}"
      ;;
  esac
}

ui_table() {
  # Args: header cols... then rows as "col1|col2|col3"
  local -a headers=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    headers+=("$1")
    shift
  done
  [[ "$1" == "--" ]] && shift

  case "$UI_BACKEND" in
    gum)
      if [[ ${#headers[@]} -gt 0 ]]; then
        gum table --border rounded --separator "|" --columns "${headers[@]}" -- "$@"
      else
        gum table --border rounded --separator "|" -- "$@"
      fi
      ;;
    *)
      if [[ ${#headers[@]} -gt 0 ]]; then
        printf '%s | ' "${headers[@]}"
        echo ""
        printf '%.0s-' {1..60}
        echo ""
      fi
      local row
      for row in "$@"; do
        echo "$row" | tr '|' ' | '
      done
      ;;
  esac
}

ui_pager() {
  local content="$1"
  case "$UI_BACKEND" in
    gum)
      echo "$content" | gum pager
      ;;
    *)
      echo "$content"
      echo ""
      ui_confirm "Продолжить?" true
      ;;
  esac
}

ui_spin() {
  local title="$1"
  shift
  case "$UI_BACKEND" in
    gum)
      gum spin --spinner dot --title "$title" -- "$@"
      ;;
    *)
      echo "$title..."
      "$@"
      ;;
  esac
}

ui_offer_gum_install() {
  command -v gum >/dev/null 2>&1 && return 0
  [[ "${NONINTERACTIVE:-0}" == "1" ]] && return 0

  ui_info "Для красивого интерфейса можно установить gum (https://github.com/charmbracelet/gum)"
  ui_confirm "Попробовать установить gum в ~/.local/bin?" false || return 0

  local arch os url bin_dir
  arch="$(uname -m)"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      ui_warn "Автоустановка gum не поддерживается для архитектуры $arch"
      return 1
      ;;
  esac

  bin_dir="${HOME}/.local/bin"
  mkdir -p "$bin_dir"
  url="https://github.com/charmbracelet/gum/releases/latest/download/gum_${os}_${arch}.tar.gz"

  ui_spin "Скачивание gum" bash -c "
    set -euo pipefail
    tmp=\$(mktemp -d)
    trap 'rm -rf \"\$tmp\"' EXIT
    curl -fsSL \"$url\" | tar -xz -C \"\$tmp\"
    install -m 755 \"\$tmp/gum\" \"$bin_dir/gum\"
  " || {
    ui_warn "Не удалось установить gum, будет использован простой интерфейс"
    return 1
  }

  export PATH="$bin_dir:$PATH"
  ui_success "gum установлен в $bin_dir/gum"
  UI_BACKEND="gum"
}
