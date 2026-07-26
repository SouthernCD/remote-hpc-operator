#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  diagnose_sge_job.sh --machine <machine_id> --job-id <job_id>

Description:
  Explain why an SGE job may be pending, where it is running, and what output is available.

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
TMP_DIR="${REMOTE_WORK_ROOT}/_agent_runs/_tmp_diagnose_${JOB_ID}"
mkdir -p "\${TMP_DIR}"
QSTAT_J="\${TMP_DIR}/qstat_j.txt"
QSTAT_F="\${TMP_DIR}/qstat_f.txt"
qstat -j "${JOB_ID}" > "\${QSTAT_J}" 2>&1 || true
qstat -f > "\${QSTAT_F}" 2>&1 || true

printf -- '--- scheduler detail ---\n'
cat "\${QSTAT_J}"
printf -- '\n--- heuristic ---\n'
if grep -qi 'Following jobs do not exist' "\${QSTAT_J}"; then
  echo "job is no longer in active qstat output; check qacct if accounting is enabled"
elif grep -qi 'cannot run in queue' "\${QSTAT_J}"; then
  echo "job is blocked by queue/resource constraints; inspect the lines above for the exact queue and resource mismatch"
elif grep -qi 'error reason' "\${QSTAT_J}"; then
  echo "scheduler reported an explicit error reason; inspect qstat -j output"
else
  echo "no explicit scheduler block detected; inspect queue summary and job logs"
fi
printf -- '\n--- queue summary ---\n'
qstat 2>&1 | awk -v job_id="${JOB_ID}" 'NR==1 || \$1 == job_id { print }' || true
EOF
)

ssh_login_script <<<"${REMOTE_SCRIPT}"
