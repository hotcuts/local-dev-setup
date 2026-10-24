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
  local version=$2
  local sha=$3
  state_set "${name}_version" "$version"
  state_set "${name}_sha256" "$sha"
}

apply_versioned_file() {
  local name=$1
  local version=$2
  local src=$3
  local dest=$4
  local condition=$5
  local repo_sha recorded_version recorded_sha

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

  case "$version" in
    ''|*[!0-9]*)
      echo "error: version must be an integer for $name" >&2
      return 1
      ;;
  esac

  repo_sha="$(file_sha256 "$src")"
  recorded_version="$(state_get "${name}_version")"
  recorded_sha="$(state_get "${name}_sha256")"

  if [[ ! -f "$dest" ]]; then
    if [[ -e "$dest" ]]; then
      echo "error: $dest exists and is not a file" >&2
      return 1
    fi
    install_managed_file "$src" "$dest"
    record_state "$name" "$version" "$repo_sha"
    note_changed "$name"
    return 0
  fi

  if [[ -z "$recorded_version" || "$version" -gt "$recorded_version" ]]; then
    if cmp -s "$src" "$dest"; then
      record_state "$name" "$version" "$repo_sha"
      note_unchanged "$name"
    else
      backup_file "$name" "$dest"
      install_managed_file "$src" "$dest"
      record_state "$name" "$version" "$repo_sha"
      note_changed "$name"
    fi
    return 0
  fi

  if [[ "$version" -eq "$recorded_version" ]]; then
    if [[ "$recorded_sha" != "$repo_sha" ]]; then
      echo "warning: ${name} version ${version} content changed without a version bump; not applying" >&2
      note_unchanged "$name"
      return 0
    fi
    note_unchanged "$name"
    return 0
  fi

  note_unchanged "$name"
}

apply_manifest() {
  local manifest=$1
  local line name version src rest dest condition

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|\#*) continue ;;
    esac

    read -r name version src rest <<< "$line"
    [[ -n "${rest:-}" ]] || {
      echo "error: invalid manifest line: $line" >&2
      return 1
    }

    condition="${rest##* }"
    dest="${rest% "$condition"}"
    dest="${dest% }"
    apply_versioned_file "$name" "$version" "$src" "$dest" "$condition"
  done < "$manifest"
}
