#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  diagnose_remote_task.sh --machine <machine_id> --project <project> --run-id <run_id>

Description:
  Collect extra diagnostics for a remote task, including file growth, process tree,
  working directory, and a simple heuristic for where the task may be stuck.

Notes:
  - --machine is required; there is no default machine.
EOF
}

PROJECT=""
RUN_ID=""

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

RUN_DIR="${RUNS_ROOT}/${PROJECT}/${RUN_ID}"
TARGET="$(
  ssh_login_script <<EOF
set -euo pipefail
cat "${RUN_DIR}/target.txt"
EOF
)"

REMOTE_SCRIPT=$(
  cat <<EOF
set -euo pipefail
cd "${RUN_DIR}"
PID=\$(cat pid.txt)
STATUS=\$(cat status.txt)
STDOUT_SIZE=\$(wc -c < stdout.log 2>/dev/null || echo 0)
STDERR_SIZE=\$(wc -c < stderr.log 2>/dev/null || echo 0)
HEARTBEAT=\$(cat heartbeat.txt 2>/dev/null || true)
NOW=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf 'status=%s\n' "\${STATUS}"
printf 'heartbeat=%s\n' "\${HEARTBEAT}"
printf 'now=%s\n' "\${NOW}"
printf 'stdout_bytes=%s\n' "\${STDOUT_SIZE}"
printf 'stderr_bytes=%s\n' "\${STDERR_SIZE}"

if ps -p "\${PID}" >/dev/null 2>&1; then
  printf 'process=alive\n'
  printf -- '--- ps ---\n'
  ps -o pid=,ppid=,pgid=,stat=,etime=,%cpu=,%mem=,command= -p "\${PID}"
  printf -- '\n--- cwd ---\n'
  pwdx "\${PID}" 2>/dev/null || true
  printf -- '\n--- process tree ---\n'
  ps -eo pid=,ppid=,stat=,etime=,command= | awk -v target="\${PID}" '
    \$1 == target || \$2 == target { print }
  '
else
  printf 'process=dead\n'
fi

printf -- '\n--- tail stdout ---\n'
tail -n 40 stdout.log 2>/dev/null || true
printf -- '\n--- tail stderr ---\n'
tail -n 40 stderr.log 2>/dev/null || true

printf -- '\n--- heuristic ---\n'
if [[ "\${STATUS}" == "running" ]] && ps -p "\${PID}" >/dev/null 2>&1; then
  if [[ "\${STDERR_SIZE}" -gt 0 ]]; then
    echo "task is alive and stderr is non-empty; inspect stderr tail first"
  elif [[ "\${STDOUT_SIZE}" -eq 0 ]]; then
    echo "task is alive but no stdout yet; it may be waiting on startup, blocked on IO, or using buffered output"
  else
    echo "task is alive and writing stdout; inspect the latest stdout lines for the current stage"
  fi
elif [[ "\${STATUS}" == "failed" ]]; then
  echo "task has failed; inspect stderr tail and exit_code.txt"
elif [[ "\${STATUS}" == "succeeded" ]]; then
  echo "task has finished successfully"
else
  echo "task state is inconclusive; inspect metadata files manually"
fi
EOF
)

ssh_target_script "${TARGET}" <<<"${REMOTE_SCRIPT}"
