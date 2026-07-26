#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  submit_sge_job.sh --machine <machine_id> --project <project> --name <job_name> --script <relative_script_path>

Description:
  Submit an existing SGE job script from the machine's configured work root and
  record qsub output under the machine's configured runs root.

Notes:
  - --machine is required; there is no default machine.
  - The selected machine must have scheduler=sge.
EOF
}

PROJECT=""
JOB_NAME=""
SCRIPT_PATH=""

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
    --name)
      JOB_NAME="${2:-}"
      shift 2
      ;;
    --script)
      SCRIPT_PATH="${2:-}"
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
require_scheduler "sge"
require_arg "${PROJECT}" "--project"
require_arg "${JOB_NAME}" "--name"
require_arg "${SCRIPT_PATH}" "--script"
ensure_project_relpath "${PROJECT}"

PROJECT_PATH="$(project_path "${PROJECT}")"
SUBMIT_ID="$(date -u +"%Y%m%dT%H%M%SZ")_${JOB_NAME}"
SUBMIT_DIR="${RUNS_ROOT}/${PROJECT}/sge_submissions/${SUBMIT_ID}"

REMOTE_SCRIPT=$(
  cat <<EOF
set -euo pipefail
mkdir -p "${SUBMIT_DIR}"
cd "${PROJECT_PATH}"
qsub_output=\$(qsub "${SCRIPT_PATH}" 2>&1)
printf '%s\n' "\${qsub_output}" | tee "${SUBMIT_DIR}/qsub_output.txt" >/dev/null
job_id=\$(printf '%s\n' "\${qsub_output}" | awk '/Your job/ {print \$3; exit}')
printf '%s\n' "${JOB_NAME}" > "${SUBMIT_DIR}/job_name.txt"
printf '%s\n' "${SCRIPT_PATH}" > "${SUBMIT_DIR}/script_path.txt"
printf '%s\n' "\${job_id}" > "${SUBMIT_DIR}/job_id.txt"
printf '%s\n' "${PROJECT}" > "${SUBMIT_DIR}/project.txt"
printf '%s\n' "$(timestamp_utc)" > "${SUBMIT_DIR}/submitted_at.txt"
printf 'submit_dir=%s\n' "${SUBMIT_DIR}"
printf 'job_id=%s\n' "\${job_id}"
printf 'qsub_output=%s\n' "\${qsub_output}"
EOF
)

ssh_login_script <<<"${REMOTE_SCRIPT}"
