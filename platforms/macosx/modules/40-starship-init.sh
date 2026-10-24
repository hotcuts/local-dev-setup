# Point .zshrc at ~/.zshdev once. The managed profile is applied from the manifest.

source_line='[[ -f "$HOME/.zshdev" ]] && source "$HOME/.zshdev"'
zshrc="${HOME}/.zshrc"

if [[ -f "$zshrc" ]] && grep -Fqx "$source_line" "$zshrc"; then
  note_unchanged "zshdev-hook"
else
  if [[ -f "$zshrc" && -s "$zshrc" ]]; then
    printf '\n%s\n' "$source_line" >> "$zshrc"
  else
    printf '%s\n' "$source_line" >> "$zshrc"
  fi
  note_changed "zshdev-hook"
fi
