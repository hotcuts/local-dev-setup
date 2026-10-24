# Ubuntu with apt only. Other distros keep the linux/ directory shape but are
# not implemented here.

os_release_file="${LOCAL_DEV_SETUP_OS_RELEASE:-/etc/os-release}"
if [[ ! -f "$os_release_file" ]]; then
  echo "error: platforms/linux requires Ubuntu (missing $os_release_file)" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$os_release_file"
if [[ "${ID:-}" != "ubuntu" && " ${ID_LIKE:-} " != *" ubuntu "* ]]; then
  echo "error: platforms/linux currently supports Ubuntu (got ID=${ID:-unknown})" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "error: apt-get is required on Ubuntu" >&2
  exit 1
fi

apt_root="${LOCAL_DEV_SETUP_APT_ROOT:-}"
export DEBIAN_FRONTEND=noninteractive

run_apt() {
  if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" != "0" ]]; then
    sudo env DEBIAN_FRONTEND=noninteractive "$@"
  else
    env DEBIAN_FRONTEND=noninteractive "$@"
  fi
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

apt_has_candidate() {
  local policy candidate
  policy="$(apt-cache policy "$1" 2>/dev/null || true)"
  candidate="$(printf '%s\n' "$policy" | awk '/Candidate:/ { print $2; exit }')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

note_unchanged "ubuntu-apt"
