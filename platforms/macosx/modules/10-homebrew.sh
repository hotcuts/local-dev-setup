# Ensure one Homebrew install and a single shellenv hook.

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "${HOME}/homebrew/bin/brew"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_homebrew() {
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

shellenv_present() {
  local file
  for file in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    [[ -f "$file" ]] || continue
    if grep -q 'brew shellenv' "$file"; then
      return 0
    fi
  done
  return 1
}

brew_bin=""
if brew_bin="$(find_brew)"; then
  note_unchanged "homebrew"
else
  install_homebrew
  brew_bin="$(find_brew)" || {
    echo "error: Homebrew install did not produce a brew binary" >&2
    exit 1
  }
  note_changed "homebrew"
fi

eval "$("${brew_bin}" shellenv)"

if shellenv_present; then
  note_unchanged "homebrew-shellenv"
else
  printf 'eval "$(%s shellenv)"\n' "$brew_bin" >> "${HOME}/.zprofile"
  note_changed "homebrew-shellenv"
fi
