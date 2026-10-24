#!/bin/bash
# Exercises install.sh against a temp HOME and a fake brew. No real installs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPS=()

cleanup() {
  local dir
  if [[ ${#TMPS[@]} -eq 0 ]]; then
    return
  fi
  for dir in "${TMPS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

die() {
  echo "FAIL: $*" >&2
  exit 1
}

keep() {
  TMPS+=("$1")
}

setup_fixture() {
  FIX="$(mktemp -d)"
  HOME_DIR="$(mktemp -d)"
  FAKE_BIN="$(mktemp -d)"
  keep "$FIX"
  keep "$HOME_DIR"
  keep "$FAKE_BIN"

  cp "$ROOT/install.sh" "$FIX/install.sh"
  cp -R "$ROOT/lib" "$FIX/lib"
  cp -R "$ROOT/platforms" "$FIX/platforms"
  cp -R "$ROOT/config" "$FIX/config"
  chmod +x "$FIX/install.sh" "$FIX/platforms/"*/install.sh

  # Keep Ghostty detection inside the temp home so this machine's app does not leak in.
  sed -i '' "s#app:/Applications/Ghostty.app#app:${HOME_DIR}/Applications/Ghostty.app#" \
    "$FIX/platforms/macosx/manifest.conf"

  cat > "$FAKE_BIN/brew" << 'EOF'
#!/bin/bash
printf 'HOMEBREW_NO_AUTO_UPDATE=%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-}" >> "${BREW_LOG:?}"
printf '%s\n' "$*" >> "$BREW_LOG"
if [[ "${1:-}" == "shellenv" ]]; then
  printf 'export HOMEBREW_PREFIX="%s"\n' "${FAKE_BREW_PREFIX:?}"
fi
exit 0
EOF
  chmod +x "$FAKE_BIN/brew"

  BREW_LOG="$FIX/brew.log"
  : > "$BREW_LOG"
  export HOME="$HOME_DIR"
  export PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  export BREW_LOG FAKE_BREW_PREFIX="$FAKE_BIN"
  unset LOCAL_DEV_SETUP_PLATFORM || true
}

run_install() {
  local code
  set +e
  bash "$FIX/install.sh" >"$FIX/stdout" 2>"$FIX/err"
  code=$?
  set -e
  printf '%s\n' "$code"
}

starship_dest() {
  printf '%s\n' "$HOME_DIR/.config/starship.toml"
}

ghostty_dest() {
  printf '%s\n' "$HOME_DIR/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
}

assert_file_equals() {
  local expected=$1 actual=$2
  cmp -s "$expected" "$actual" || die "files differ: $actual vs $expected"
}

echo "RUN repo declares the macOS baseline"
grep -q 'brew "starship"' "$ROOT/platforms/macosx/Brewfile" || die "missing starship formula"
grep -q 'cask "ghostty"' "$ROOT/platforms/macosx/Brewfile" || die "missing ghostty cask"
grep -q 'cask "font-jetbrains-mono-nerd-font"' "$ROOT/platforms/macosx/Brewfile" || die "missing nerd font cask"
grep -q 'cask "zed"' "$ROOT/platforms/macosx/Brewfile" || die "missing zed cask"
grep -q 'cask "google-chrome"' "$ROOT/platforms/macosx/Brewfile" || die "missing chrome cask"
grep -q 'cask "firefox"' "$ROOT/platforms/macosx/Brewfile" || die "missing firefox cask"
grep -q 'hotcuts/local-dev-setup' "$ROOT/install.sh" || die "install.sh is not pinned to hotcuts/local-dev-setup"
echo "PASS repo declares the macOS baseline"

echo "RUN darwin dispatch selects macosx"
[[ "$(uname -s)" == "Darwin" ]] || die "these tests run on macOS"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "darwin install exited $code: $(cat "$FIX/err")"
grep -q 'Applying platform macosx' "$FIX/stdout" || die "darwin dispatch did not select macosx"
echo "PASS darwin dispatch selects macosx"

echo "RUN linux stub exits non-zero"
setup_fixture
export LOCAL_DEV_SETUP_PLATFORM=linux
code="$(run_install)"
[[ "$code" != "0" ]] || die "linux stub exited 0"
grep -q 'platforms/linux is not implemented yet' "$FIX/err" || die "missing linux stub message: $(cat "$FIX/err")"
[[ ! -s "$BREW_LOG" ]] || die "linux stub invoked brew"
unset LOCAL_DEV_SETUP_PLATFORM
echo "PASS linux stub exits non-zero"

echo "RUN unknown platform lists available directories"
setup_fixture
export LOCAL_DEV_SETUP_PLATFORM=plan9
code="$(run_install)"
[[ "$code" != "0" ]] || die "unknown platform exited 0"
grep -q 'macosx' "$FIX/err" || die "available platforms omitted macosx"
grep -q 'linux' "$FIX/err" || die "available platforms omitted linux"
grep -q 'windows' "$FIX/err" || die "available platforms omitted windows"
unset LOCAL_DEV_SETUP_PLATFORM
echo "PASS unknown platform lists available directories"

echo "RUN second run writes nothing and starship init is added once"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "first install exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
[[ ! -f "$(ghostty_dest)" ]] || die "ghostty config was written without the app"
grep -q 'bundle check --file=' "$BREW_LOG" || die "brew bundle check was not invoked: $(cat "$BREW_LOG")"
grep -q "platforms/macosx/Brewfile" "$BREW_LOG" || die "brew bundle did not use the macOS Brewfile"
grep -q 'HOMEBREW_NO_AUTO_UPDATE=1' "$BREW_LOG" || die "brew auto-update was not disabled"
source_line='[[ -f "$HOME/.zshdev" ]] && source "$HOME/.zshdev"'
starship_line='eval "$(starship init zsh)"'
source_count="$(grep -Fxc "$source_line" "$HOME_DIR/.zshrc")"
[[ "$source_count" == "1" ]] || die "zshdev source count is $source_count after first run"
if grep -Fq "$starship_line" "$HOME_DIR/.zshrc"; then
  die "starship init was written into .zshrc"
fi
assert_file_equals "$FIX/platforms/macosx/config/zshdev" "$HOME_DIR/.zshdev"
grep -Fqx "$starship_line" "$HOME_DIR/.zshdev" || die "starship init missing from .zshdev"
shellenv_count="$(grep -Fc 'brew shellenv' "$HOME_DIR/.zprofile")"
[[ "$shellenv_count" == "1" ]] || die "brew shellenv count is $shellenv_count"
before_sha="$(shasum -a 256 "$(starship_dest)" | awk '{print $1}')"
: > "$BREW_LOG"
code="$(run_install)"
[[ "$code" == "0" ]] || die "second install exited $code: $(cat "$FIX/err")"
after_sha="$(shasum -a 256 "$(starship_dest)" | awk '{print $1}')"
[[ "$before_sha" == "$after_sha" ]] || die "second run changed starship.toml"
[[ ! -d "$HOME_DIR/.local/share/local-dev-setup/backups" ]] || die "second run created a backup"
source_count="$(grep -Fxc "$source_line" "$HOME_DIR/.zshrc")"
[[ "$source_count" == "1" ]] || die "zshdev source count is $source_count after second run"
assert_file_equals "$FIX/platforms/macosx/config/zshdev" "$HOME_DIR/.zshdev"
shellenv_count="$(grep -Fc 'brew shellenv' "$HOME_DIR/.zprofile")"
[[ "$shellenv_count" == "1" ]] || die "brew shellenv was duplicated"
grep -qx 'unchanged: starship' "$FIX/stdout" || die "second run did not report starship unchanged"
echo "PASS second run writes nothing and starship init is added once"

echo "RUN deleted config is restored at the same version"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "install before delete exited $code"
rm -f "$(starship_dest)"
code="$(run_install)"
[[ "$code" == "0" ]] || die "restore install exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
echo "PASS deleted config is restored at the same version"

echo "RUN ghostty config is written only when the app exists"
setup_fixture
mkdir -p "$HOME_DIR/Applications/Ghostty.app"
code="$(run_install)"
[[ "$code" == "0" ]] || die "ghostty install exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/platforms/macosx/config/ghostty.config" "$(ghostty_dest)"
grep -q 'font-family = JetBrainsMono Nerd Font' "$(ghostty_dest)" || die "font family was not applied"
grep -q 'font-size = 16' "$(ghostty_dest)" || die "font size was not applied"
echo "PASS ghostty config is written only when the app exists"

echo "RUN version bump replaces the file and keeps a backup"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "baseline install exited $code"
old_copy="$(mktemp)"
keep "$old_copy"
cp "$(starship_dest)" "$old_copy"
printf '\n# local-dev-setup test bump\n' >> "$FIX/config/starship.toml"
sed -i '' 's/^starship 1 /starship 2 /' "$FIX/platforms/macosx/manifest.conf"
code="$(run_install)"
[[ "$code" == "0" ]] || die "version bump exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
backup="$(find "$HOME_DIR/.local/share/local-dev-setup/backups" -type f -name starship)"
[[ -n "$backup" ]] || die "version bump did not leave a backup"
cmp -s "$old_copy" "$backup" || die "backup does not match the previous starship config"
echo "PASS version bump replaces the file and keeps a backup"

echo "RUN same version with changed bytes warns and does not write"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "baseline install exited $code"
before_sha="$(shasum -a 256 "$(starship_dest)" | awk '{print $1}')"
printf '\n# forgotten bump\n' >> "$FIX/config/starship.toml"
code="$(run_install)"
[[ "$code" == "0" ]] || die "forgotten bump exited $code: $(cat "$FIX/err")"
grep -q 'warning: starship version 1 content changed without a version bump; not applying' "$FIX/err" \
  || die "missing forgotten-bump warning: $(cat "$FIX/err")"
after_sha="$(shasum -a 256 "$(starship_dest)" | awk '{print $1}')"
[[ "$before_sha" == "$after_sha" ]] || die "forgotten bump overwrote starship.toml"
echo "PASS same version with changed bytes warns and does not write"

echo "RUN an extra module runs after the built-in modules"
setup_fixture
cat > "$FIX/platforms/macosx/modules/50-extra.sh" << 'EOF'
if grep -Fqx '[[ -f "$HOME/.zshdev" ]] && source "$HOME/.zshdev"' "$HOME/.zshrc"; then
  printf '%s\n' after > "$HOME/extra-order"
else
  printf '%s\n' before > "$HOME/extra-order"
fi
printf '%s\n' ran > "$HOME/extra-ran"
EOF
code="$(run_install)"
[[ "$code" == "0" ]] || die "extra module install exited $code: $(cat "$FIX/err")"
[[ "$(cat "$HOME_DIR/extra-ran")" == "ran" ]] || die "extra module did not run"
[[ "$(cat "$HOME_DIR/extra-order")" == "after" ]] || die "extra module ran before starship init"
echo "PASS an extra module runs after the built-in modules"

echo "All install tests passed."
