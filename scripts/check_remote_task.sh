#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  check_remote_task.sh --machine <machine_id> --project <project> --run-id <run_id> [--tail <n>]

Description:
  Inspect a remote run directory and summarize command, status, heartbeat,
  process state, and the last lines of stdout/stderr.

Notes:
  - --machine is required; there is no default machine.
EOF
}

PROJECT=""
RUN_ID=""
TAIL_LINES=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --machine)
      MACHINE="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --tail)
      TAIL_LINES="${2:-}"
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
require_arg "${PROJECT}" "--project"
require_arg "${RUN_ID}" "--run-id"
ensure_project_relpath "${PROJECT}"
if [[ ! "${TAIL_LINES}" =~ ^[0-9]+$ ]]; then
  die "--tail must be a non-negative integer: ${TAIL_LINES}"
fi

RUN_DIR="${RUNS_ROOT}/${PROJECT}/${RUN_ID}"

REMOTE_SCRIPT=$(
  cat <<EOF
set -euo pipefail
cd "${RUN_DIR}"
TARGET=\$(cat target.txt)
STATUS=\$(cat status.txt)
COMMAND=\$(cat command.shlex.txt)
PID=\$(cat pid.txt)
HEARTBEAT=\$(cat heartbeat.txt 2>/dev/null || true)
EXIT_CODE=\$(cat exit_code.txt 2>/dev/null || true)
FINISHED_AT=\$(cat finished_at.txt 2>/dev/null || true)

if ps -p "\${PID}" >/dev/null 2>&1; then
  PROC_STATE="alive"
  PS_LINE=\$(ps -o pid=,ppid=,stat=,etime=,%cpu=,%mem=,command= -p "\${PID}" | sed 's/^[[:space:]]*//')
else
  PROC_STATE="dead"
  PS_LINE=""
fi

printf 'target=%s\n' "\${TARGET}"
printf 'status=%s\n' "\${STATUS}"
printf 'pid=%s\n' "\${PID}"
printf 'process_state=%s\n' "\${PROC_STATE}"
printf 'heartbeat=%s\n' "\${HEARTBEAT}"
printf 'exit_code=%s\n' "\${EXIT_CODE}"
printf 'finished_at=%s\n' "\${FINISHED_AT}"
printf 'command=%s\n' "\${COMMAND}"
printf 'ps_line=%s\n' "\${PS_LINE}"
printf -- '--- stdout tail ---\n'
tail -n ${TAIL_LINES} stdout.log 2>/dev/null || true
printf -- '\n--- stderr tail ---\n'
tail -n ${TAIL_LINES} stderr.log 2>/dev/null || true
EOF
)

TARGET="$(
  ssh_login_script <<EOF
set -euo pipefail
cat "${RUN_DIR}/target.txt"
EOF
)"
ssh_target_script "${TARGET}" <<<"${REMOTE_SCRIPT}"
