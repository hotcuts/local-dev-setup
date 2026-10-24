# Install the declarative package list. Check first so a satisfied Brewfile is a no-op.

brewfile="${PLATFORM_DIR}/Brewfile"
if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$brewfile"; then
  note_unchanged "brew-bundle"
else
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$brewfile"
  note_changed "brew-bundle"
fi
