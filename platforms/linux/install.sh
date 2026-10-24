#!/bin/bash
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${PLATFORM_DIR}/../.." && pwd)"
export LOCAL_DEV_SETUP_ROOT="$ROOT"

# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
common_init

printf 'Applying platform linux\n'

module=""
for module in "${PLATFORM_DIR}"/modules/*.sh; do
  [[ -f "$module" ]] || continue
  # shellcheck disable=SC1090
  source "$module"
done

print_summary
