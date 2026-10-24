#!/bin/bash
# Curl entrypoint for hotcuts/local-dev-setup.
# A checkout with platforms/ dispatches to that OS. Anything else clones the repo and re-execs.
set -euo pipefail

REPO="${LOCAL_DEV_SETUP_REPO:-hotcuts/local-dev-setup}"
REF="${LOCAL_DEV_SETUP_REF:-main}"
CHECKOUT="${HOME}/.local/share/local-dev-setup/repo"

script_dir() {
  local src="${BASH_SOURCE[0]}"
  while [[ -L "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

detect_platform() {
  if [[ -n "${LOCAL_DEV_SETUP_PLATFORM:-}" ]]; then
    printf '%s\n' "$LOCAL_DEV_SETUP_PLATFORM"
    return 0
  fi

  local uname_s
  uname_s="$(uname -s)"
  case "$uname_s" in
    Darwin) printf '%s\n' macosx ;;
    Linux) printf '%s\n' linux ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) printf '%s\n' windows ;;
    *)
      echo "Unrecognized operating system: $uname_s" >&2
      return 1
      ;;
  esac
}

list_platforms() {
  local root=$1
  local dir
  echo "Available platforms:" >&2
  for dir in "$root"/platforms/*; do
    [[ -d "$dir" ]] || continue
    basename "$dir" >&2
  done
}

bootstrap() {
  if [[ "${LOCAL_DEV_SETUP_BOOTSTRAPPED:-}" == "1" ]]; then
    echo "error: checked out installer is missing platforms/" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$CHECKOUT")"
  if [[ -d "$CHECKOUT/.git" ]]; then
    git -C "$CHECKOUT" fetch --depth 1 origin "$REF"
    git -C "$CHECKOUT" reset --hard FETCH_HEAD
  else
    rm -rf "$CHECKOUT"
    git clone --depth 1 --branch "$REF" "https://github.com/${REPO}.git" "$CHECKOUT"
  fi

  export LOCAL_DEV_SETUP_BOOTSTRAPPED=1
  exec "$CHECKOUT/install.sh"
}

main() {
  local root=""
  local platform=""
  local installer=""

  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    root="$(script_dir)"
  fi

  if [[ -z "$root" || ! -d "$root/platforms" ]]; then
    bootstrap
  fi

  platform="$(detect_platform)" || exit 1
  installer="$root/platforms/$platform/install.sh"
  if [[ ! -f "$installer" ]]; then
    echo "No installer for platform: $platform" >&2
    list_platforms "$root"
    exit 1
  fi

  exec "$installer"
}

main "$@"
