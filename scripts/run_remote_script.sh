#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  run_remote_script.sh --machine <machine_id> --target <node> --name <label> < script.sh

Description:
  Run a medium-complexity bash script on a documented remote target by passing
  the script over stdin. This avoids fragile nested SSH quoting for commands
  that contain pipes, quotes, variables, awk/sed, loops, or environment setup.

Notes:
  - --machine is required; there is no default machine.
  - --target is required and must be a node allowed by the machine profile.
  - --name is a local audit label printed with the execution summary.
  - This helper does not copy the script to remote storage; use long-task or
    scheduler helpers when the operation needs durable remote metadata.
EOF
}

TARGET=""
RUN_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --machine)
      MACHINE="${2:-}"
      shift 2
      ;;
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --name)
      RUN_NAME="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

load_machine_config
require_arg "${TARGET}" "--target"
require_arg "${RUN_NAME}" "--name"

if is_forbidden_business_target "${TARGET}"; then
  die "refusing to run script on forbidden business target for machine ${MACHINE}: ${TARGET}"
fi

TMP_SCRIPT="$(mktemp)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT
cat > "${TMP_SCRIPT}"

if [[ ! -s "${TMP_SCRIPT}" ]]; then
  die "stdin did not contain a script"
fi

print_kv "name" "${RUN_NAME}"
print_kv "machine" "${MACHINE}"
print_kv "target" "${TARGET}"
print_kv "started_at" "$(timestamp_utc)"
printf -- '--- remote output ---\n'
ssh_target_script "${TARGET}" < "${TMP_SCRIPT}"
