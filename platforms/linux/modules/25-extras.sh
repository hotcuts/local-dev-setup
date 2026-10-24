# Tools Ubuntu does not ship the way we need them: Starship, nvm, Chrome, Zed,
# and JetBrainsMono Nerd Font.

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_starship() {
  if have_cmd starship || [[ -x "${HOME}/.local/bin/starship" ]]; then
    note_unchanged "starship"
    return 0
  fi
  mkdir -p "${HOME}/.local/bin"
  curl -sS https://starship.rs/install.sh | sh -s -- -y -b "${HOME}/.local/bin"
  note_changed "starship"
}

install_nvm() {
  if [[ -s "${HOME}/.nvm/nvm.sh" ]]; then
    note_unchanged "nvm"
    return 0
  fi
  # PROFILE=/dev/null keeps nvm from appending a second hook to ~/.zshrc.
  PROFILE=/dev/null bash -c "$(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh)"
  note_changed "nvm"
}

install_chrome() {
  if have_cmd google-chrome-stable || have_cmd google-chrome; then
    note_unchanged "google-chrome"
    return 0
  fi
  local keyring list
  keyring="${apt_root}/usr/share/keyrings/google-chrome.gpg"
  list="${apt_root}/etc/apt/sources.list.d/google-chrome.list"
  run_apt mkdir -p "$(dirname "$keyring")" "$(dirname "$list")"
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | run_apt gpg --dearmor --yes -o "$keyring"
  printf 'deb [arch=amd64 signed-by=%s] https://dl.google.com/linux/chrome/deb/ stable main\n' "$keyring" \
    | run_apt tee "$list" >/dev/null
  run_apt apt-get update
  run_apt apt-get install -y google-chrome-stable
  note_changed "google-chrome"
}

install_zed() {
  if have_cmd zed || [[ -x "${HOME}/.local/bin/zed" ]]; then
    note_unchanged "zed"
    return 0
  fi
  curl -fsSL https://zed.dev/install.sh | sh
  note_changed "zed"
}

install_nerd_font() {
  if command -v fc-list >/dev/null 2>&1 && fc-list | grep -qi 'JetBrainsMono Nerd Font'; then
    note_unchanged "nerd-font"
    return 0
  fi
  local dest zip
  dest="${HOME}/.local/share/fonts/JetBrainsMonoNerd"
  if ls "$dest"/*.ttf >/dev/null 2>&1; then
    note_unchanged "nerd-font"
    return 0
  fi
  mkdir -p "$dest"
  zip="$(mktemp)"
  curl -fsSL -o "$zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
  unzip -qo "$zip" -d "$dest"
  rm -f "$zip"
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$dest" >/dev/null
  fi
  note_changed "nerd-font"
}

install_starship
install_nvm
install_chrome
install_zed
install_nerd_font
