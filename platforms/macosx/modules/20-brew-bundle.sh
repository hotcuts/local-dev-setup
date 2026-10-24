# Install the declarative package list. An app that is already on disk and is not a
# Homebrew cask is left alone: adopting it runs `chgrp` and macOS often returns
# "Operation not permitted" for apps installed outside Homebrew.

cask_is_brew_managed() {
  brew list --cask "$1" >/dev/null 2>&1
}

cask_app_names() {
  local name=$1
  local json
  json="$(brew info --cask --json=v2 "$name" 2>/dev/null || true)"
  [[ -n "$json" ]] || return 0
  printf '%s\n' "$json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for cask in data.get("casks", []):
    for artifact in cask.get("artifacts", []):
        if not isinstance(artifact, dict) or "app" not in artifact:
            continue
        apps = artifact["app"]
        if isinstance(apps, str):
            apps = [apps]
        for app in apps:
            print(app)
'
}

app_already_present() {
  local app_name=$1
  if [[ -n "${LOCAL_DEV_SETUP_APPLICATIONS:-}" ]]; then
    [[ -d "${LOCAL_DEV_SETUP_APPLICATIONS}/${app_name}" ]]
    return
  fi
  [[ -d "/Applications/${app_name}" || -d "${HOME}/Applications/${app_name}" ]]
}

cask_should_skip() {
  local name=$1
  local app
  if cask_is_brew_managed "$name"; then
    return 1
  fi
  while IFS= read -r app; do
    [[ -z "$app" ]] && continue
    if app_already_present "$app"; then
      return 0
    fi
  done < <(cask_app_names "$name")
  return 1
}

prepare_brewfile() {
  local src=$1
  local dest line trimmed token skipped
  dest="${HOME}/.local/share/local-dev-setup/Brewfile"
  mkdir -p "$(dirname "$dest")"
  : > "$dest"
  skipped=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      'cask "'*)
        token="${trimmed#cask \"}"
        token="${token%%\"*}"
        if cask_should_skip "$token"; then
          printf '# skipped: %s is already installed and is not a Homebrew cask\n' "$token" >> "$dest"
          note_skipped "$token"
          skipped=1
          continue
        fi
        ;;
    esac
    printf '%s\n' "$line" >> "$dest"
  done < "$src"
  if [[ "$skipped" -eq 0 ]]; then
    rm -f "$dest"
    EFFECTIVE_BREWFILE="$src"
    return 0
  fi
  EFFECTIVE_BREWFILE="$dest"
}

EFFECTIVE_BREWFILE=""
prepare_brewfile "${PLATFORM_DIR}/Brewfile"
brewfile="$EFFECTIVE_BREWFILE"
if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$brewfile"; then
  note_unchanged "brew-bundle"
else
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$brewfile"
  note_changed "brew-bundle"
fi
