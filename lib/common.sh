# Shared installer engine. Source this file; do not execute it.
# Callers must set ROOT to the repository root before applying manifests.

common_init() {
  CHANGED=0
  UNCHANGED=0
  SKIPPED=0
  LOCAL_DEV_SETUP_BACKUP_STAMP="$(date +%Y%m%dT%H%M%S)"
  export LOCAL_DEV_SETUP_BACKUP_STAMP
}

note_changed() {
  CHANGED=$((CHANGED + 1))
  printf 'changed: %s\n' "$1"
}

note_unchanged() {
  UNCHANGED=$((UNCHANGED + 1))
  printf 'unchanged: %s\n' "$1"
}

note_skipped() {
  SKIPPED=$((SKIPPED + 1))
  printf 'skipped: %s\n' "$1"
}

print_summary() {
  printf 'summary: changed=%s unchanged=%s skipped=%s\n' "$CHANGED" "$UNCHANGED" "$SKIPPED"
}

state_file() {
  printf '%s\n' "${HOME}/.local/share/local-dev-setup/state.env"
}

state_get() {
  local key=$1
  local file line
  file="$(state_file)"
  [[ -f "$file" ]] || return 0
  line="$(grep "^${key}=" "$file" || true)"
  line="${line##*$'\n'}"
  [[ -n "$line" ]] || return 0
  printf '%s\n' "${line#*=}"
}

state_set() {
  local key=$1
  local value=$2
  local file tmp
  file="$(state_file)"
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    grep -v "^${key}=" "$file" > "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

state_unset() {
  local key=$1
  local file tmp
  file="$(state_file)"
  [[ -f "$file" ]] || return 0
  grep -q "^${key}=" "$file" || return 0
  tmp="$(mktemp)"
  grep -v "^${key}=" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}

file_sha256() {
  shasum -a 256 "$1" | awk 'NR==1 { print $1 }'
}

expand_dest() {
  local path=$1
  case "$path" in
    \~)
      printf '%s\n' "$HOME"
      ;;
    \~/*)
      printf '%s\n' "$HOME/${path#\~/}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

condition_met() {
  local condition=$1
  case "$condition" in
    -)
      return 0
      ;;
    app:*)
      [[ -e "${condition#app:}" ]]
      ;;
    cmd:*)
      command -v "${condition#cmd:}" >/dev/null 2>&1
      ;;
    *)
      echo "error: unknown condition: $condition" >&2
      return 1
      ;;
  esac
}

backup_file() {
  local name=$1
  local dest=$2
  local dir="${HOME}/.local/share/local-dev-setup/backups/${LOCAL_DEV_SETUP_BACKUP_STAMP}"
  mkdir -p "$dir"
  cp "$dest" "$dir/$name"
}

install_managed_file() {
  local src=$1
  local dest=$2
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

record_state() {
  local name=$1
  local sha=$2
  state_set "${name}_sha256" "$sha"
  # Older installs tracked a manual version number. Nothing reads it any more.
  state_unset "${name}_version"
}

# Write a repo file to its destination when the repo file has changed since the last apply.
#   missing destination        -> write it
#   repo file unchanged        -> leave the destination alone, including hand edits
#   repo file changed          -> back up the destination, then write the repo file
apply_managed_file() {
  local name=$1
  local src=$2
  local dest=$3
  local condition=$4
  local repo_sha recorded_sha

  if ! condition_met "$condition"; then
    note_skipped "$name"
    return 0
  fi

  case "$src" in
    /*) ;;
    *) src="${ROOT}/${src}" ;;
  esac
  dest="$(expand_dest "$dest")"

  [[ -f "$src" ]] || {
    echo "error: missing config source: $src" >&2
    return 1
  }

  repo_sha="$(file_sha256 "$src")"
  recorded_sha="$(state_get "${name}_sha256")"

  if [[ ! -f "$dest" ]]; then
    if [[ -e "$dest" ]]; then
      echo "error: $dest exists and is not a file" >&2
      return 1
    fi
    install_managed_file "$src" "$dest"
    record_state "$name" "$repo_sha"
    note_changed "$name"
    return 0
  fi

  if [[ "$recorded_sha" == "$repo_sha" ]]; then
    record_state "$name" "$repo_sha"
    note_unchanged "$name"
    return 0
  fi

  if cmp -s "$src" "$dest"; then
    record_state "$name" "$repo_sha"
    note_unchanged "$name"
    return 0
  fi

  backup_file "$name" "$dest"
  install_managed_file "$src" "$dest"
  record_state "$name" "$repo_sha"
  note_changed "$name"
}

apply_manifest() {
  local manifest=$1
  local line name src rest dest condition

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|\#*) continue ;;
    esac

    read -r name src rest <<< "$line"
    [[ -n "${rest:-}" ]] || {
      echo "error: invalid manifest line: $line" >&2
      return 1
    }

    condition="${rest##* }"
    dest="${rest% "$condition"}"
    dest="${dest% }"
    apply_managed_file "$name" "$src" "$dest" "$condition"
  done < "$manifest"
}
