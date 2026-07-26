#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  start_remote_task.sh --machine <machine_id> --project <project> --target <node> --name <run_name> -- <command...>

Description:
  Start a long-running task on a remote node and record metadata, stdout, stderr,
  heartbeat, PID, and exit code under the machine's configured runs root.

Notes:
  - --machine is required; there is no default machine.
  - Do not use nodes marked as forbidden_business_targets for business commands.
  - The project path is always interpreted relative to the machine's configured work root.
EOF
}

PROJECT=""
TARGET=""
RUN_NAME=""

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
    --)
      shift
      break
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

load_machine_config
require_arg "${PROJECT}" "--project"
require_arg "${TARGET}" "--target"
require_arg "${RUN_NAME}" "--name"
ensure_project_relpath "${PROJECT}"

if [[ $# -eq 0 ]]; then
  die "missing command after --"
fi

if is_forbidden_business_target "${TARGET}"; then
  die "refusing to start business command on forbidden target for machine ${MACHINE}: ${TARGET}"
fi

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")_${RUN_NAME}"
PROJECT_PATH="$(project_path "${PROJECT}")"
RUN_DIR="${RUNS_ROOT}/${PROJECT}/${RUN_ID}"
COMMAND_TEXT="$(printf "%q " "$@")"
STARTED_AT="$(timestamp_utc)"

REMOTE_SCRIPT=$(
  cat <<EOF
set -euo pipefail
mkdir -p "${PROJECT_PATH}" "${RUN_DIR}"
cd "${RUN_DIR}"
printf '%s\n' "${RUN_ID}" > run_id.txt
printf '%s\n' "${RUN_NAME}" > run_name.txt
printf '%s\n' "${MACHINE}" > machine.txt
printf '%s\n' "${PROJECT}" > project.txt
printf '%s\n' "${PROJECT_PATH}" > project_path.txt
printf '%s\n' "${TARGET}" > target.txt
printf '%s\n' "${STARTED_AT}" > started_at.txt
printf '%s\n' "launching" > status.txt
printf '%s\n' "${COMMAND_TEXT}" > command.shlex.txt
printf '%s\n' "$$" > launcher_pid.txt

cat > run_wrapper.sh <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
cd "${RUN_DIR}"
printf '%s\n' "running" > status.txt
date -u +"%Y-%m-%dT%H:%M:%SZ" > heartbeat.txt
(
  while true; do
    date -u +"%Y-%m-%dT%H:%M:%SZ" > heartbeat.txt
    sleep 30
  done
) &
HEARTBEAT_PID=\$!
printf '%s\n' "\${HEARTBEAT_PID}" > heartbeat_pid.txt

bash -lc '
  set -euo pipefail
  cd "'"${PROJECT_PATH}"'"
  exec '"${COMMAND_TEXT}"'
' >stdout.log 2>stderr.log &
TASK_PID=\$!
printf '%s\n' "\${TASK_PID}" > pid.txt

wait "\${TASK_PID}"
EXIT_CODE=\$?
printf '%s\n' "\${EXIT_CODE}" > exit_code.txt
if [[ "\${EXIT_CODE}" -eq 0 ]]; then
  printf '%s\n' "succeeded" > status.txt
else
  printf '%s\n' "failed" > status.txt
fi
date -u +"%Y-%m-%dT%H:%M:%SZ" > finished_at.txt
kill "\${HEARTBEAT_PID}" >/dev/null 2>&1 || true
wait "\${HEARTBEAT_PID}" 2>/dev/null || true
RUNNER

chmod +x run_wrapper.sh
nohup bash run_wrapper.sh >/dev/null 2>&1 &
printf '%s\n' "\$!" > runner_pid.txt
EOF
)

ssh_target_script "${TARGET}" <<<"${REMOTE_SCRIPT}" >/dev/null

print_kv "run_id" "${RUN_ID}"
print_kv "machine" "${MACHINE}"
print_kv "target" "${TARGET}"
print_kv "project" "${PROJECT}"
print_kv "run_dir" "${RUN_DIR}"
print_kv "command" "${COMMAND_TEXT}"
