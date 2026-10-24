# local-dev-setup

Forkable installer for a macOS dev machine. macOS is the implemented platform. Linux and Windows have the same directory shape and are not implemented yet.

```bash
curl -fsSL https://raw.githubusercontent.com/hotcuts/local-dev-setup/main/install.sh | bash
```

`install.sh` is the only public entry. When it is piped through curl, it clones `hotcuts/local-dev-setup` into `~/.local/share/local-dev-setup/repo` and runs that checkout. When `platforms/` is already next to the script, it selects a platform and runs `platforms/<os>/install.sh`.

Override the slug or git ref for one run:

```bash
LOCAL_DEV_SETUP_REPO=you/your-fork LOCAL_DEV_SETUP_REF=main bash install.sh
```

`LOCAL_DEV_SETUP_PLATFORM` forces `macosx`, `linux`, or `windows` instead of detecting `uname`.

## Layout

```
install.sh                          curl entry and OS dispatch
lib/common.sh                       config apply, state, backups
config/starship.toml                Tones pad prompt, shared across platforms
platforms/macosx/install.sh         sources modules in lexical order
platforms/macosx/modules/*.sh       Homebrew, Brewfile, configs, .zshdev hook
platforms/macosx/Brewfile           taps, formulae, and casks
platforms/macosx/manifest.conf      config files to manage
platforms/macosx/config/            macOS-only app config
platforms/linux/install.sh          not implemented
platforms/windows/install.sh        not implemented
```

OS map: `Darwin` to `macosx`, `Linux` to `linux`, and `MINGW` / `MSYS` / `CYGWIN` / `Windows_NT` to `windows`.

## What macOS installs

`platforms/macosx/Brewfile`:

- `starship`
- `zsh-syntax-highlighting`, loaded from `~/.zshdev` (syntax highlighting last)
- `AUTO_CD` enabled in `~/.zshdev`, so typing a directory name (or `..`) changes into it without `cd`
- `nvm` and `go`; `~/.zshdev` uses Homebrew's nvm only when `nvm` is not already loaded by `~/.zshrc`
- Ghostty
- JetBrainsMono Nerd Font
- Zed
- Google Chrome
- Firefox

Homebrew is installed with the official non-interactive installer only when `brew` is missing. An existing install is reused, including `~/homebrew`. The search order is `PATH`, `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`, then `~/homebrew/bin/brew`. A `brew shellenv` line is appended to `~/.zprofile` only when neither `~/.zprofile` nor `~/.zshrc` already has one. A cask whose app is already in `/Applications` or `~/Applications`, and which Homebrew does not own, is skipped. Adopting those apps runs `chgrp`, and macOS returns "Operation not permitted". Delete the app and re-run if Homebrew should install that cask.

Shell setup for this installer lives in `~/.zshdev`, including `eval "$(starship init zsh)"`. Zsh does not load that file on its own, so `~/.zshrc` gets one line when it is missing:

```bash
[[ -f "$HOME/.zshdev" ]] && source "$HOME/.zshdev"
```

Nothing else in `~/.zshrc` is added or removed. Oh My Zsh, nvm, and gcloud stay where they are. Later changes to the profile reach `~/.zshdev` on the next run.

Ghostty gets a font config only when `/Applications/Ghostty.app` exists:

```
font-family = JetBrainsMono Nerd Font
font-size = 16
```

That family string matches the installed JetBrainsMono Nerd Font. Zed, Chrome, and Firefox are installed as casks only.

## Idempotency

Running the same revision twice changes nothing. Package state comes from `brew bundle check`. Config state lives in `~/.local/share/local-dev-setup/state.env`.

For each row in the platform manifest:

- The app condition fails: skip that file. The font cask still installs.
- The destination is missing: write it.
- The repo file is the same as the last time it was applied: leave the destination alone, including local edits.
- The repo file changed since the last apply: back up the live file under `~/.local/share/local-dev-setup/backups/<timestamp>/` and write the repo file.
- There is no record yet and the live file differs from the repo file: back it up and write the repo file.

The installer records a SHA-256 of each repo file it applies. There are no version numbers to maintain. Git history is the version history.

## Change a config

1. Edit the file, for example `config/starship.toml`.
2. Re-run `install.sh`.

The next run sees that the repo file changed, backs up the live file, and writes the new one. A run after that changes nothing. Edits you make directly to the live file are kept until the repo file changes again.

Manifest fields are `name`, `src`, `dest`, and `condition`. Paths in `src` are relative to the repo root. `dest` may start with `~/`. `condition` is `-` or `app:/absolute/path`.

```
starship config/starship.toml ~/.config/starship.toml -
ghostty platforms/macosx/config/ghostty.config ~/Library/Application Support/com.mitchellh.ghostty/config.ghostty app:/Applications/Ghostty.app
```

## Add a package

Add a line to `platforms/macosx/Brewfile` and re-run:

```ruby
brew "jq"
cask "visual-studio-code"
```

## Add a module

Drop a numbered script into `platforms/macosx/modules/`. `platforms/macosx/install.sh` sources `*.sh` in lexical order. A fork can add `50-gitconfig.sh` without editing the dispatcher. Modules share the shell, so they can call `apply_managed_file` and `note_changed` from `lib/common.sh`. A module must be safe to run twice.

## Fork

1. Change `REPO` in `install.sh` from `hotcuts/local-dev-setup` to your `user/repo`, so the curl entry clones the fork.
2. Edit that platform's Brewfile, manifest, and config files.
3. Add modules under `platforms/<os>/modules/`.
4. Leave `install.sh` and `lib/common.sh` alone unless you are changing dispatch or how configs are applied.

To implement Linux or Windows later, replace that platform's `install.sh` and add its own modules, package list, and manifest. The root dispatcher stays as it is.

## Tests

```bash
bash tests/install_test.sh
```

The tests use a temporary home directory and a fake `brew`. They do not install Homebrew, fonts, or apps.
