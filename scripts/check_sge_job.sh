#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  check_sge_job.sh --machine <machine_id> --job-id <job_id>

Description:
  Query SGE for current job status, queue placement, and scheduler explanation.

Notes:
  - --machine is required; there is no default machine.
  - The selected machine must have scheduler=sge.
EOF
}

JOB_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --machine)
      MACHINE="${2:-}"
      shift 2
      ;;
    --job-id)
      JOB_ID="${2:-}"
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
require_arg "${JOB_ID}" "--job-id"

REMOTE_SCRIPT=$(
  cat <<EOF
set -euo pipefail
printf -- '--- qstat -j ---\n'
qstat -j "${JOB_ID}" 2>&1 || true
printf -- '\n--- qstat summary ---\n'
qstat 2>&1 | awk -v job_id="${JOB_ID}" 'NR==1 || \$1 == job_id { print }' || true
printf -- '\n--- qhost ---\n'
qhost 2>&1 || true
EOF
)

ssh_login_script <<<"${REMOTE_SCRIPT}"
