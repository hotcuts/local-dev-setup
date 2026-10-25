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
if [[ "${1:-}" == "list" && "${2:-}" == "--cask" ]]; then
  if [[ -n "${BREW_UNMANAGED_CASKS:-}" && -f "${BREW_UNMANAGED_CASKS}/${3:-}" ]]; then
    exit 1
  fi
  exit 0
fi
if [[ "${1:-}" == "info" && "${2:-}" == "--cask" && "${3:-}" == "--json=v2" ]]; then
  info_file="${BREW_CASK_INFO:-}/${4:-}"
  if [[ -f "$info_file" ]]; then
    cat "$info_file"
  fi
  exit 0
fi
exit 0
EOF
  chmod +x "$FAKE_BIN/brew"

  BREW_LOG="$FIX/brew.log"
  APT_LOG="$FIX/apt.log"
  CURL_LOG="$FIX/curl.log"
  INSTALLED_PKGS="$FIX/installed-pkgs"
  : > "$BREW_LOG"
  : > "$APT_LOG"
  : > "$CURL_LOG"
  : > "$INSTALLED_PKGS"

  cat > "$FAKE_BIN/sudo" << 'EOF'
#!/bin/bash
exec "$@"
EOF

  cat > "$FAKE_BIN/dpkg-query" << 'EOF'
#!/bin/bash
pkg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -W) shift ;;
    -f*) shift ;;
    *) pkg=$1; shift ;;
  esac
done
if grep -qx "$pkg" "${INSTALLED_PKGS:?}"; then
  printf 'install ok installed\n'
  exit 0
fi
exit 1
EOF

  cat > "$FAKE_BIN/apt-get" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${APT_LOG:?}"
if [[ "${1:-}" == "update" ]]; then
  exit 0
fi
if [[ "${1:-}" == "install" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-y" ]]; then
      shift
      continue
    fi
    printf '%s\n' "$1" >> "${INSTALLED_PKGS:?}"
    stub=""
    case "$1" in
      ghostty) stub=ghostty ;;
      golang-go) stub=go ;;
      firefox) stub=firefox ;;
      google-chrome-stable) stub=google-chrome-stable ;;
    esac
    if [[ -n "$stub" ]]; then
      printf '#!/bin/sh\n' > "${FAKE_BIN:?}/$stub"
      chmod +x "${FAKE_BIN}/$stub"
    fi
    shift
  done
fi
exit 0
EOF

  cat > "$FAKE_BIN/apt-cache" << 'EOF'
#!/bin/bash
if [[ "${1:-}" == "policy" ]]; then
  printf 'Candidate: 1.3.0\n'
fi
exit 0
EOF

  cat > "$FAKE_BIN/add-apt-repository" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${APT_LOG:?}"
exit 0
EOF

  cat > "$FAKE_BIN/gpg" << 'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    *) shift ;;
  esac
done
cat >/dev/null
if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  : > "$out"
fi
exit 0
EOF

  cat > "$FAKE_BIN/fc-list" << 'EOF'
#!/bin/bash
exit 0
EOF

  cat > "$FAKE_BIN/fc-cache" << 'EOF'
#!/bin/bash
exit 0
EOF

  cat > "$FAKE_BIN/curl" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${CURL_LOG:?}"
out=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) out=$2; shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  *starship.rs/install.sh*)
    cat << 'SCRIPT'
#!/bin/bash
bindir="${HOME}/.local/bin"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b) bindir=$2; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$bindir"
printf '#!/bin/sh\n' > "$bindir/starship"
chmod +x "$bindir/starship"
SCRIPT
    ;;
  *nvm-sh/nvm*)
    cat << 'SCRIPT'
#!/bin/bash
mkdir -p "${HOME}/.nvm"
printf '# nvm\n' > "${HOME}/.nvm/nvm.sh"
SCRIPT
    ;;
  *zed.dev/install.sh*)
    cat << 'SCRIPT'
#!/bin/bash
mkdir -p "${HOME}/.local/bin"
printf '#!/bin/sh\n' > "${HOME}/.local/bin/zed"
chmod +x "${HOME}/.local/bin/zed"
SCRIPT
    ;;
  *JetBrainsMono.zip*)
    target="${out:-/dev/stdout}"
    python3 - "$target" << 'PY'
import sys, zipfile, io
dest = sys.argv[1]
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as zf:
    zf.writestr("JetBrainsMonoNerdFont-Regular.ttf", b"ttf")
data = buf.getvalue()
if dest == "/dev/stdout":
    sys.stdout.buffer.write(data)
else:
    open(dest, "wb").write(data)
PY
    ;;
  *linux_signing_key.pub*)
    printf 'KEY\n'
    ;;
esac
exit 0
EOF

  chmod +x "$FAKE_BIN/sudo" "$FAKE_BIN/dpkg-query" "$FAKE_BIN/apt-get" \
    "$FAKE_BIN/apt-cache" "$FAKE_BIN/add-apt-repository" "$FAKE_BIN/gpg" \
    "$FAKE_BIN/fc-list" "$FAKE_BIN/fc-cache" "$FAKE_BIN/curl"

  export HOME="$HOME_DIR"
  export PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  export BREW_LOG APT_LOG CURL_LOG INSTALLED_PKGS FAKE_BIN FAKE_BREW_PREFIX="$FAKE_BIN"
  unset LOCAL_DEV_SETUP_PLATFORM LOCAL_DEV_SETUP_OS_RELEASE LOCAL_DEV_SETUP_APT_ROOT || true
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
for formula in zsh-autosuggestions zsh-syntax-highlighting nvm go; do
  grep -qx "brew \"$formula\"" "$ROOT/platforms/macosx/Brewfile" || die "missing $formula formula"
done
zshdev_src="$ROOT/config/zshdev"
! grep -q 'zsh-autocomplete.plugin.zsh' "$zshdev_src" || die "zshdev should not load zsh-autocomplete"
grep -q 'up-line-or-beginning-search' "$zshdev_src" || die "zshdev does not configure up-line-or-beginning-search"
grep -q 'zsh-autosuggestions.zsh' "$zshdev_src" || die "zshdev does not load zsh-autosuggestions"
grep -q '/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' "$zshdev_src" || die "zshdev does not load Ubuntu zsh-autosuggestions"
grep -q 'zsh-syntax-highlighting.zsh' "$zshdev_src" || die "zshdev does not load zsh-syntax-highlighting"
grep -q 'opt/nvm/nvm.sh' "$zshdev_src" || die "zshdev does not load Homebrew nvm"
grep -q 'NVM_DIR/nvm.sh' "$zshdev_src" || die "zshdev does not load ~/.nvm"
auto_cd_state="$(env -i HOME="$(mktemp -d)" PATH="/usr/bin:/bin" HOMEBREW_PREFIX=/nonexistent \
  zsh -f -c 'source "$1" 2>/dev/null; [[ -o autocd ]] && echo on || echo off' _ "$zshdev_src" 2>/dev/null || true)"
[[ "$auto_cd_state" == "on" ]] || die "zshdev does not enable AUTO_CD (got: $auto_cd_state)"
syntax_line="$(grep -n 'zsh-syntax-highlighting.zsh' "$zshdev_src" | tail -n 1 | cut -d: -f1)"
last_line="$(grep -vn '^[[:space:]]*\(#\|$\)' "$zshdev_src" | tail -n 1 | cut -d: -f1)"
[[ "$syntax_line" -ge "$last_line" || "$(sed -n "${syntax_line},\$p" "$zshdev_src" | grep -c 'source\|^\.')" -le 1 ]] \
  || die "zsh-syntax-highlighting must be sourced last"
grep -q 'hotcuts/local-dev-setup' "$ROOT/install.sh" || die "install.sh is not pinned to hotcuts/local-dev-setup"
echo "PASS repo declares the macOS baseline"

echo "RUN Tones pad starship theme"
sp="$ROOT/config/starship.toml"
grep -q 'Tones pad' "$sp" || die "starship.toml is not named Tones pad"
grep -q '#fbb829' "$sp" || die "starship.toml does not use the Srcery palette"
for old in ffc600 3ad900 ff628c 0088ff 132738 0d2233 e6eef7 8a9bb5; do
  grep -qi "#$old" "$sp" && die "starship.toml still has Cobalt2 color #$old"
done
grep -q 'bg:' "$sp" || die "Tones pad uses powerline segments, which need backgrounds"
python3 - "$sp" << 'PY' || die "Tones pad layout is wrong"
import sys, tomllib
cfg = tomllib.load(open(sys.argv[1], "rb"))
assert cfg["format"].count("$line_break") == 1, "the info row and caret must be adjacent so the ╭─ ╰─ bars meet"
first, sep, rest = cfg["format"].partition("$line_break")
assert sep, "format needs a $line_break between the two lines"
order = ["$os", "$directory", "$nodejs", "$bun", "$golang", "$rust", "$php", "$git_branch", "$git_status", "$git_state", "$fill", "$cmd_duration", "$status", "$time"]
for mod in order:
    assert mod in first, mod + " must be on line 1"
positions = [first.index(m) for m in order]
assert positions == sorted(positions), "line 1 accordion is os, dir, lang, git, fill, duration, status, clock"
assert "$hostname" not in cfg["format"] and "hostname" not in cfg, "the right side is reserved for duration/status/clock, not host"
lang_group_start = first.index("([", 0)
assert lang_group_start < first.index("$nodejs") < first.index("$git_branch"), "language sits in one accordion group between directory and git"
assert first.index("$php") < first.index("${custom.lang_to_git}"), "language joins git with a pink-to-green arrow"
assert first.index("${custom.dir_to_git}") < first.index("$git_branch"), "git still has a yellow-to-green arrow when language is absent"
assert "fbb829" not in cfg["git_branch"]["format"], "git must not hard-code a directory arrow; the accordion customs own that join"
# Duration on the right is its own group so it vanishes when the command was fast.
dur_group_start = first.index("([", first.index("$fill"))
assert dur_group_start < first.index("$cmd_duration") < first.index("$status")
assert first.index("$nodejs") < first.index("$fill"), "language belongs on the left, not the duration group"
assert "╭─" in first and "╰─" in rest, "connector lines are missing"
assert "$directory" not in rest, "line 2 is the input line only"
assert "$character" in rest, "line 2 needs the character module for the caret"
assert "[╰─]" in rest and "[╰─ ]" not in rest, "caret sits against the connector with no extra space"
for key in ("success_symbol", "error_symbol"):
    assert "❯]" in cfg["character"][key], key + " is just the caret, no trailing spaces"
assert cfg.get("right_format", "") == "", "the right side lives on line 1 via $fill, not right_format"
for mod in ("os", "status", "time"):
    assert cfg[mod]["disabled"] is False, mod + " must be enabled"
gs = cfg["git_status"]
assert "$ahead_behind" in gs["format"], "ahead/behind must come from $ahead_behind"
assert "$stashed" in gs["format"] and "$untracked" in gs["format"]
assert gs["ahead"].startswith("⇡") and "${count}" in gs["ahead"]
assert gs["behind"].startswith("⇣") and "${count}" in gs["behind"]
assert "⇣" in gs["diverged"] and "⇡" in gs["diverged"]
assert gs["stashed"].startswith("*")
assert gs["conflicted"].startswith("~")
assert gs["staged"].startswith("+")
assert gs["modified"].startswith("!")
assert gs["untracked"].startswith("?")
assert "$state" in cfg["git_state"]["format"]
assert cfg["directory"]["truncation_length"] == 1, "accordion directory is the current folder only"
for key in ("lang_to_git", "end_lang", "dir_to_git"):
    assert key in cfg["custom"], "missing accordion join " + key
for lang in ("nodejs", "bun", "golang", "rust", "php"):
    assert "#ff5c8f" in cfg[lang]["format"], lang + " must share the pink language slice"
PY
real_starship="$(command -v starship || true)"
if [[ -n "$real_starship" ]]; then
  # TERM=dumb makes starship exit early without reading the config, so set a real one.
  starship_cache="$(mktemp -d)"
  keep "$starship_cache"
  render() {
    # usage: render <dir> [starship prompt args...]; prints the prompt with colors stripped.
    local dir=$1
    shift
    (cd "$dir" && TERM=xterm-256color STARSHIP_CACHE="$starship_cache" STARSHIP_CONFIG="$sp" \
      "$real_starship" prompt --terminal-width 100 "$@" 2>>"$starship_cache/stderr") \
      | python3 -c 'import re,sys; print(re.sub(r"%\{|%\}|\x1b\[[0-9;]*m", "", sys.stdin.read()), end="")'
  }
  plain_dir="$(mktemp -d)/work"
  mkdir -p "$plain_dir"
  keep "$(dirname "$plain_dir")"

  # Starship only validates modules it renders, so render a plain dir and failing status.
  : > "$starship_cache/stderr"
  out_ok="$(render "$plain_dir" --status 0)"
  out_fail="$(render "$plain_dir" --status 1)"
  out_slow="$(render "$plain_dir" --status 0 --cmd-duration 3000)"
  warnings="$(cat "$starship_cache/stderr")"
  if printf '%s' "$warnings" | grep -Eq 'ERROR|WARN'; then
    die "starship rejected the config: $warnings"
  fi
  python3 - "$out_ok" "$out_fail" "$out_slow" << 'PY' || die "Tones pad render is wrong"
import re, socket, sys
ok, fail, slow = sys.argv[1], sys.argv[2], sys.argv[3]
host = socket.gethostname().split(".")[0]
lines = ok.split("\n")
nonempty = [l for l in lines if l.strip()]
assert len(nonempty) == 2, "expected exactly two prompt lines, got: " + repr(ok)
assert len([l for l in lines if l.strip() or l == ""]) < 4, "a blank row would gap the ╭─ ╰─ bars: " + repr(ok)
l1, l2 = nonempty[0], nonempty[1]
assert l1.startswith("╭─") and l2.startswith("╰─"), "connectors are wrong: " + repr(ok)
assert "❯" in l2, "line 2 needs the caret: " + repr(l2)
assert re.match(r"^╰─❯", l2), "caret should sit against the connector: " + repr(l2)
assert "work" in l1, "directory missing on line 1"
assert re.search(r"\d\d:\d\d", l1), "clock missing from line 1"
assert "✔" in l1 and "✘" not in l1, "success status should show a check"
assert "✘" in fail and "✔" not in fail, "failed status should show a cross"
assert "❯" in [l for l in fail.split("\n") if l.strip()][1], "caret must stay after a failed command"
assert len(l1.rstrip()) >= 90, "right side was not pushed to the edge by $fill: " + repr(l1)

# No host name or home icon on the right.
assert "\uf015" not in l1, "home icon must not be on line 1"
if len(host) >= 4:
    assert host not in l1, "host name must not be on line 1"

# The runtime segment only exists when it has content, and brings exactly one pair of arrows.
slow_l1 = next(l for l in slow.split("\n") if l.strip())
assert "took 3s" not in l1 and "took 3s" in slow_l1, "command duration belongs in the runtime segment"
assert slow_l1.count("\ue0b2") == l1.count("\ue0b2") + 1, "runtime segment should add one left arrow"
assert slow_l1.count("\ue0b0") == l1.count("\ue0b0") + 1, "runtime segment should add one right arrow"
assert l1.count("\ue0b2") == 2, "with no runtime info only status and clock arrows remain: " + repr(l1)
PY

  # Git segments: only run where git can create a repo (some sandboxes block it).
  git_dir="$(mktemp -d)/repo"
  mkdir -p "$git_dir"
  keep "$(dirname "$git_dir")"
  if git -C "$git_dir" init -q -b tonesbranch 2>/dev/null && git -C "$git_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$git_dir" config user.email 'tones@example.test'
    git -C "$git_dir" config user.name 'Tones'
    git_out="$(render "$git_dir" --status 0)"
    printf '%s' "$git_out" | grep -q 'tonesbranch' || die "git branch missing in a repo: $git_out"
    printf '%s' "$out_ok" | grep -q 'tonesbranch' && die "git branch leaked outside a repo"

    printf 'new\n' > "$git_dir/untracked.txt"
    untracked_out="$(render "$git_dir" --status 0)"
    printf '%s' "$untracked_out" | grep -q '?1' || die "untracked count missing: $untracked_out"

    git -C "$git_dir" add untracked.txt
    staged_out="$(render "$git_dir" --status 0)"
    printf '%s' "$staged_out" | grep -q '+1' || die "staged count missing: $staged_out"
    printf '%s' "$staged_out" | grep -q '?1' && die "staged file still counted as untracked: $staged_out"

    git -C "$git_dir" commit -qm 'init'
    printf 'edit\n' >> "$git_dir/untracked.txt"
    modified_out="$(render "$git_dir" --status 0)"
    printf '%s' "$modified_out" | grep -q '!1' || die "modified count missing: $modified_out"

    git -C "$git_dir" stash push -q -m 'park'
    stash_out="$(render "$git_dir" --status 0)"
    printf '%s' "$stash_out" | grep -q '*1' || die "stash count missing: $stash_out"
    printf '%s' "$stash_out" | grep -q '!1' && die "stashed change still counted as modified: $stash_out"

    git -C "$git_dir" remote add origin "$git_dir/../origin.git"
    git -C "$git_dir" config branch.tonesbranch.remote origin
    git -C "$git_dir" config branch.tonesbranch.merge refs/heads/tonesbranch
    git -C "$git_dir" update-ref refs/remotes/origin/tonesbranch HEAD
    printf 'ahead\n' >> "$git_dir/untracked.txt"
    git -C "$git_dir" add untracked.txt
    git -C "$git_dir" commit -qm 'ahead'
    git -C "$git_dir" update-ref refs/remotes/origin/tonesbranch HEAD~
    ahead_out="$(render "$git_dir" --status 0)"
    printf '%s' "$ahead_out" | grep -q '⇡1' || die "ahead count missing: $ahead_out"

    git -C "$git_dir" update-ref refs/remotes/origin/tonesbranch HEAD
    git -C "$git_dir" update-ref HEAD HEAD~
    behind_out="$(render "$git_dir" --status 0)"
    printf '%s' "$behind_out" | grep -q '⇣1' || die "behind count missing: $behind_out"
  else
    echo "SKIP git segment render (git could not create a repo here)"
  fi

  lang_dir="$(mktemp -d)/app"
  mkdir -p "$lang_dir"
  keep "$(dirname "$lang_dir")"
  printf '%s\n' '{"name":"app"}' > "$lang_dir/package.json"
  lang_out="$(render "$lang_dir" --status 0)"
  printf '%s' "$lang_out" | grep -q 'app' || die "directory missing in a language project: $lang_out"
  printf '%s' "$lang_out" | grep -q 'tonesbranch' && die "git leaked into a language-only directory: $lang_out"
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$lang_out" | grep -Eq 'v?[0-9]+\.[0-9]+' || die "language slice missing a version: $lang_out"
    python3 - "$out_ok" "$lang_out" << 'PY' || die "language accordion did not add a left-side slice"
import sys
plain, lang = sys.argv[1], sys.argv[2]
plain_l1 = next(l for l in plain.split("\n") if l.strip())
lang_l1 = next(l for l in lang.split("\n") if l.strip())
assert lang_l1.count("\ue0b0") == plain_l1.count("\ue0b0") + 1, "language should add one right arrow: " + repr(lang_l1)
assert "took" not in lang_l1, "language must not sit in the duration group"
PY
  else
    echo "SKIP language version render (node is not installed)"
  fi

  if [[ -d "$git_dir" ]] && git -C "$git_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' '{"name":"app"}' > "$git_dir/package.json"
    both_out="$(render "$git_dir" --status 0)"
    printf '%s' "$both_out" | grep -q 'tonesbranch' || die "git missing when language is also present: $both_out"
    if command -v node >/dev/null 2>&1; then
      printf '%s' "$both_out" | grep -Eq 'v?[0-9]+\.[0-9]+' || die "language slice missing next to git: $both_out"
    fi
  fi
fi
grep -q 'theme = Srcery' "$ROOT/config/ghostty.config" || die "ghostty theme is not Srcery"
opacity="$(sed -n 's/^background-opacity = //p' "$ROOT/config/ghostty.config")"
python3 -c 'import sys; v = float(sys.argv[1]); assert 0 < v <= 1, v' "$opacity" 2>/dev/null \
  || die "ghostty background-opacity must be a number above 0 and at most 1 (got: $opacity)"
! grep -Eq '^background-blur[[:space:]]*=[[:space:]]*([1-9][0-9]*|true|on)[[:space:]]*$' \
  "$ROOT/config/ghostty.config" || die "ghostty must not enable background blur"
grep -q '^adjust-cell-height = 40%$' "$ROOT/config/ghostty.config" || die "ghostty line height is not 40% for prompt padding"
gc="$ROOT/config/ghostty.config"
grep -q '^cursor-style = block$' "$gc" || die "ghostty cursor is not a block"
grep -q '^cursor-style-blink = true$' "$gc" || die "ghostty cursor does not blink"
grep -q '^cursor-color = #98bc37$' "$gc" || die "ghostty cursor should match the green caret"
# Shell integration forces a bar cursor at the prompt unless the cursor feature is off.
grep -q '^shell-integration-features = no-cursor$' "$gc" || die "shell integration would override the block cursor"
theme_file="/Applications/Ghostty.app/Contents/Resources/ghostty/themes/Srcery"
if [[ -f "$theme_file" ]]; then
  python3 - "$sp" "$theme_file" << 'PY2' || die "Ghostty theme and Starship colors have drifted apart"
import re, sys
starship = set(c.lower() for c in re.findall(r"#[0-9a-fA-F]{6}", open(sys.argv[1], encoding="utf-8").read()))
theme_text = open(sys.argv[2]).read().lower()
theme = set(re.findall(r"#[0-9a-f]{6}", theme_text))
# #303030 is the status panel: a step lighter than the background, deliberately not a theme color.
missing = sorted(c for c in starship - {"#303030"} if c not in theme)
assert not missing, "starship colors missing from the Ghostty theme: " + ", ".join(missing)
bg = re.search(r"^background = (#[0-9a-f]{6})", theme_text, re.M).group(1)
assert bg == "#1c1b19", "Ghostty background changed: " + bg
PY2
fi
ghostty_bin=/Applications/Ghostty.app/Contents/MacOS/ghostty
if [[ -x "$ghostty_bin" ]]; then
  ghostty_out="$("$ghostty_bin" +validate-config --config-file="$ROOT/config/ghostty.config" 2>&1)" || ghostty_rc=$?
  if [[ "${ghostty_rc:-0}" != 0 && "$ghostty_out" != *SentryInitFailed* ]]; then
    die "ghostty rejected its config: $ghostty_out"
  fi
fi
echo "PASS Tones pad starship theme"

echo "RUN darwin dispatch selects macosx"
[[ "$(uname -s)" == "Darwin" ]] || die "these tests run on macOS"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "darwin install exited $code: $(cat "$FIX/err")"
grep -q 'Applying platform macosx' "$FIX/stdout" || die "darwin dispatch did not select macosx"
echo "PASS darwin dispatch selects macosx"

echo "RUN repo declares the Ubuntu baseline"
grep -qx 'zsh' "$ROOT/platforms/linux/packages.list" || die "linux packages.list missing zsh"
for pkg in zsh-autosuggestions zsh-syntax-highlighting golang-go firefox ghostty; do
  grep -qx "$pkg" "$ROOT/platforms/linux/packages.list" || die "linux packages.list missing $pkg"
done
grep -q 'starship.rs/install.sh' "$ROOT/platforms/linux/modules/25-extras.sh" || die "linux does not install Starship from its official script"
grep -q 'nvm-sh/nvm' "$ROOT/platforms/linux/modules/25-extras.sh" || die "linux does not install nvm from nvm-sh"
grep -q 'dl.google.com/linux/chrome' "$ROOT/platforms/linux/modules/25-extras.sh" || die "linux does not use Google's Chrome apt repo"
grep -q 'zed.dev/install.sh' "$ROOT/platforms/linux/modules/25-extras.sh" || die "linux does not install Zed from its official script"
grep -q 'JetBrainsMono.zip' "$ROOT/platforms/linux/modules/25-extras.sh" || die "linux does not install JetBrainsMono Nerd Font"
grep -q '~/.config/ghostty/config' "$ROOT/platforms/linux/manifest.conf" || die "linux Ghostty path is not XDG"
grep -q 'cmd:ghostty' "$ROOT/platforms/linux/manifest.conf" || die "linux Ghostty config is not gated on the binary"
echo "PASS repo declares the Ubuntu baseline"

echo "RUN linux ubuntu install uses apt not brew"
setup_fixture
export LOCAL_DEV_SETUP_PLATFORM=linux
export LOCAL_DEV_SETUP_OS_RELEASE="$FIX/os-release"
export LOCAL_DEV_SETUP_APT_ROOT="$HOME_DIR/apt-root"
printf 'ID=ubuntu\n' > "$FIX/os-release"
code="$(run_install)"
[[ "$code" == "0" ]] || die "linux install exited $code: $(cat "$FIX/err") $(cat "$FIX/stdout")"
grep -q 'Applying platform linux' "$FIX/stdout" || die "linux dispatch did not select linux"
[[ ! -s "$BREW_LOG" ]] || die "linux invoked brew: $(cat "$BREW_LOG")"
grep -q 'install -y' "$APT_LOG" || die "apt-get install was not invoked: $(cat "$APT_LOG")"
for pkg in zsh zsh-autosuggestions zsh-syntax-highlighting golang-go firefox ghostty google-chrome-stable; do
  grep -qx "$pkg" "$INSTALLED_PKGS" || die "linux did not install $pkg"
done
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
assert_file_equals "$FIX/config/zshdev" "$HOME_DIR/.zshdev"
assert_file_equals "$FIX/config/ghostty.config" "$HOME_DIR/.config/ghostty/config"
grep -Fqx '[[ -f "$HOME/.zshdev" ]] && source "$HOME/.zshdev"' "$HOME_DIR/.zshrc" || die "linux did not hook .zshdev"
[[ -x "$HOME_DIR/.local/bin/starship" ]] || die "starship was not installed to ~/.local/bin"
[[ -s "$HOME_DIR/.nvm/nvm.sh" ]] || die "nvm was not installed to ~/.nvm"
[[ -x "$HOME_DIR/.local/bin/zed" ]] || die "zed was not installed to ~/.local/bin"
ls "$HOME_DIR/.local/share/fonts/JetBrainsMonoNerd"/*.ttf >/dev/null 2>&1 || die "JetBrainsMono Nerd Font was not installed"
[[ -f "$HOME_DIR/apt-root/etc/apt/sources.list.d/google-chrome.list" ]] || die "Chrome apt source was not written under APT_ROOT"
: > "$APT_LOG"
code="$(run_install)"
[[ "$code" == "0" ]] || die "linux second install exited $code: $(cat "$FIX/err")"
grep -qx 'unchanged: apt-packages' "$FIX/stdout" || die "linux second run did not reuse apt packages"
grep -qx 'unchanged: starship' "$FIX/stdout" || die "linux second run reinstalled starship"
unset LOCAL_DEV_SETUP_PLATFORM LOCAL_DEV_SETUP_OS_RELEASE LOCAL_DEV_SETUP_APT_ROOT
echo "PASS linux ubuntu install uses apt not brew"

echo "RUN linux rejects a non-Ubuntu distro"
setup_fixture
export LOCAL_DEV_SETUP_PLATFORM=linux
export LOCAL_DEV_SETUP_OS_RELEASE="$FIX/os-release"
printf 'ID=fedora\n' > "$FIX/os-release"
code="$(run_install)"
[[ "$code" != "0" ]] || die "fedora linux install exited 0"
grep -q 'currently supports Ubuntu' "$FIX/err" || die "missing ubuntu-only message: $(cat "$FIX/err")"
[[ ! -s "$BREW_LOG" ]] || die "fedora path invoked brew"
unset LOCAL_DEV_SETUP_PLATFORM LOCAL_DEV_SETUP_OS_RELEASE
echo "PASS linux rejects a non-Ubuntu distro"

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
assert_file_equals "$FIX/config/zshdev" "$HOME_DIR/.zshdev"
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
assert_file_equals "$FIX/config/zshdev" "$HOME_DIR/.zshdev"
shellenv_count="$(grep -Fc 'brew shellenv' "$HOME_DIR/.zprofile")"
[[ "$shellenv_count" == "1" ]] || die "brew shellenv was duplicated"
grep -qx 'unchanged: starship' "$FIX/stdout" || die "second run did not report starship unchanged"
echo "PASS second run writes nothing and starship init is added once"

echo "RUN deleted config is restored"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "install before delete exited $code"
rm -f "$(starship_dest)"
code="$(run_install)"
[[ "$code" == "0" ]] || die "restore install exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
echo "PASS deleted config is restored"

echo "RUN ghostty config is written only when the app exists"
setup_fixture
mkdir -p "$HOME_DIR/Applications/Ghostty.app"
code="$(run_install)"
[[ "$code" == "0" ]] || die "ghostty install exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/ghostty.config" "$(ghostty_dest)"
grep -q 'font-family = JetBrainsMono Nerd Font' "$(ghostty_dest)" || die "font family was not applied"
grep -q 'font-size = 16' "$(ghostty_dest)" || die "font size was not applied"
echo "PASS ghostty config is written only when the app exists"

echo "RUN a changed repo config is applied automatically and backed up"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "baseline install exited $code"
old_copy="$(mktemp)"
keep "$old_copy"
cp "$(starship_dest)" "$old_copy"
printf '\n# edited in the repo, no version bump anywhere\n' >> "$FIX/config/starship.toml"
code="$(run_install)"
[[ "$code" == "0" ]] || die "config update exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
grep -qx 'changed: starship' "$FIX/stdout" || die "update was not reported: $(cat "$FIX/stdout")"
backup="$(find "$HOME_DIR/.local/share/local-dev-setup/backups" -type f -name starship)"
[[ -n "$backup" ]] || die "update did not leave a backup"
cmp -s "$old_copy" "$backup" || die "backup does not match the previous starship config"
code="$(run_install)"
[[ "$code" == "0" ]] || die "re-run after update exited $code"
grep -qx 'unchanged: starship' "$FIX/stdout" || die "re-run after an update should change nothing"
[[ "$(find "$HOME_DIR/.local/share/local-dev-setup/backups" -type f -name starship | wc -l | tr -d ' ')" == "1" ]] \
  || die "re-run after an update made another backup"
echo "PASS a changed repo config is applied automatically and backed up"

echo "RUN hand edits survive while the repo file is unchanged"
setup_fixture
code="$(run_install)"
[[ "$code" == "0" ]] || die "baseline install exited $code"
printf '\n# my local tweak\n' >> "$(starship_dest)"
code="$(run_install)"
[[ "$code" == "0" ]] || die "re-run exited $code: $(cat "$FIX/err")"
grep -q 'my local tweak' "$(starship_dest)" || die "a hand edit was overwritten although the repo file did not change"
grep -qx 'unchanged: starship' "$FIX/stdout" || die "hand-edited config should report unchanged"
[[ ! -d "$HOME_DIR/.local/share/local-dev-setup/backups" ]] || die "an unchanged repo file caused a backup"
echo "PASS hand edits survive while the repo file is unchanged"

echo "RUN the manifest has no version column"
python3 - "$ROOT/platforms/macosx/manifest.conf" << 'PY2' || die "manifest still carries version numbers"
import sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    fields = line.split()
    assert not fields[1].isdigit(), "version column found: " + line
    assert "/" in fields[1], "second field should be the source path: " + line
PY2
! grep -q 'version' "$ROOT/platforms/macosx/manifest.conf" || die "manifest header still mentions version"
echo "PASS the manifest has no version column"

echo "RUN state from the old version scheme migrates"
setup_fixture
mkdir -p "$HOME_DIR/.config" "$HOME_DIR/.local/share/local-dev-setup"
printf 'old prompt\n' > "$(starship_dest)"
printf 'starship_version=7\nstarship_sha256=0000\n' > "$HOME_DIR/.local/share/local-dev-setup/state.env"
code="$(run_install)"
[[ "$code" == "0" ]] || die "migration run exited $code: $(cat "$FIX/err")"
assert_file_equals "$FIX/config/starship.toml" "$(starship_dest)"
grep -q 'starship_version' "$HOME_DIR/.local/share/local-dev-setup/state.env" && die "legacy version key was left in state.env"
grep -q '^starship_sha256=' "$HOME_DIR/.local/share/local-dev-setup/state.env" || die "sha was not recorded"
echo "PASS state from the old version scheme migrates"

echo "RUN an existing app outside Homebrew is not adopted"
setup_fixture
export LOCAL_DEV_SETUP_APPLICATIONS="$HOME_DIR/Applications"
mkdir -p "$LOCAL_DEV_SETUP_APPLICATIONS/Zed.app"
BREW_UNMANAGED_CASKS="$FIX/unmanaged"
BREW_CASK_INFO="$FIX/cask-info"
mkdir -p "$BREW_UNMANAGED_CASKS" "$BREW_CASK_INFO"
: > "$BREW_UNMANAGED_CASKS/zed"
printf '%s\n' '{"casks":[{"token":"zed","artifacts":[{"app":["Zed.app"]}]}]}' > "$BREW_CASK_INFO/zed"
export BREW_UNMANAGED_CASKS BREW_CASK_INFO
code="$(run_install)"
[[ "$code" == "0" ]] || die "unmanaged app install exited $code: $(cat "$FIX/err")"
grep -qx 'skipped: zed' "$FIX/stdout" || die "zed was not skipped: $(cat "$FIX/stdout")"
effective="${HOME_DIR}/.local/share/local-dev-setup/Brewfile"
grep -q 'skipped: zed is already installed and is not a Homebrew cask' "$effective" || die "filtered Brewfile missing zed skip"
if grep -q 'cask "zed"' "$effective"; then
  die "filtered Brewfile still installs zed"
fi
grep -q 'cask "ghostty"' "$effective" || die "filtered Brewfile dropped ghostty"
grep -q -- "--file=${effective}" "$BREW_LOG" || die "brew bundle did not use the filtered Brewfile: $(cat "$BREW_LOG")"
unset LOCAL_DEV_SETUP_APPLICATIONS BREW_UNMANAGED_CASKS BREW_CASK_INFO
echo "PASS an existing app outside Homebrew is not adopted"

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
