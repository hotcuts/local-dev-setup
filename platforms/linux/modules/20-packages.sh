# Install the apt package list. Skip a package that is already installed.

ensure_ghostty_apt() {
  if pkg_installed ghostty || apt_has_candidate ghostty; then
    return 0
  fi
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    echo "error: ghostty is not in apt; install software-properties-common for the Ubuntu PPA fallback" >&2
    exit 1
  fi
  run_apt add-apt-repository -y ppa:mkasberg/ghostty-ubuntu
  run_apt apt-get update
  note_changed "ghostty-ppa"
}

missing=()
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    ''|\#*) continue ;;
  esac
  pkg="$line"
  if [[ "$pkg" == "ghostty" ]]; then
    ensure_ghostty_apt
  fi
  if pkg_installed "$pkg"; then
    continue
  fi
  missing+=("$pkg")
done < "${PLATFORM_DIR}/packages.list"

if [[ ${#missing[@]} -eq 0 ]]; then
  note_unchanged "apt-packages"
else
  run_apt apt-get update
  run_apt apt-get install -y "${missing[@]}"
  note_changed "apt-packages"
fi
