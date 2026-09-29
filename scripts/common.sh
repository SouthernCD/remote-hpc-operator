#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_MACHINE_CONFIG_DIR="${SKILL_ROOT}/references/machines/local"
MACHINE_CONFIG_DIR="${REMOTE_HPC_OPERATOR_CONFIG_DIR:-${DEFAULT_MACHINE_CONFIG_DIR}}"
MACHINE_CONFIG="${MACHINE_CONFIG_DIR}/config.tsv"
MACHINE_INDEX="${MACHINE_CONFIG_DIR}/index.md"

MACHINE=""
SSH_ALIAS=""
LOGIN_NODE=""
REMOTE_WORK_ROOT=""
RUNS_ROOT=""
SCHEDULER=""
FORBIDDEN_BUSINESS_TARGETS=""
EXECUTION_POLICY="profile_controlled"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

available_machines() {
  awk -F '\t' 'NR > 1 && $1 != "" { print "  - " $1 }' "${MACHINE_CONFIG}" 2>/dev/null || true
}

require_machine_arg() {
  if [[ -z "${MACHINE}" ]]; then
    echo "ERROR: missing required argument: --machine" >&2
    echo "Available machines:" >&2
    available_machines >&2
    exit 1
  fi
}

load_machine_config() {
  require_machine_arg

  if [[ ! -f "${MACHINE_INDEX}" ]]; then
    die "machine index not found: ${MACHINE_INDEX}; create private config from ${SKILL_ROOT}/references/machines/*.example.* or set REMOTE_HPC_OPERATOR_CONFIG_DIR"
  fi

  if [[ ! -f "${MACHINE_CONFIG}" ]]; then
    die "machine config not found: ${MACHINE_CONFIG}; create private config from ${SKILL_ROOT}/references/machines/*.example.* or set REMOTE_HPC_OPERATOR_CONFIG_DIR"
  fi

  local row
  local field_separator
  local delimited_row
  row="$(awk -F '\t' -v machine="${MACHINE}" 'NR > 1 && $1 == machine { print; found=1; exit } END { if (!found) exit 1 }' "${MACHINE_CONFIG}")" || {
    echo "ERROR: unknown machine: ${MACHINE}" >&2
    echo "Available machines:" >&2
    available_machines >&2
    exit 1
  }

  # A tab is shell whitespace, so a plain IFS=$'\t' read collapses empty TSV
  # columns. Translate tabs to a non-whitespace separator to preserve an empty
  # forbidden_business_targets column before the optional execution policy.
  field_separator=$'\034'
  delimited_row="${row//$'\t'/${field_separator}}"
  IFS="${field_separator}" read -r MACHINE SSH_ALIAS LOGIN_NODE REMOTE_WORK_ROOT RUNS_ROOT SCHEDULER FORBIDDEN_BUSINESS_TARGETS EXECUTION_POLICY <<<"${delimited_row}"

  # Keep existing private configs backward-compatible. A machine must opt in to
  # scheduler-only enforcement explicitly.
  EXECUTION_POLICY="${EXECUTION_POLICY:-profile_controlled}"

  require_arg "${SSH_ALIAS}" "ssh_alias for machine ${MACHINE}"
  require_arg "${LOGIN_NODE}" "login_node for machine ${MACHINE}"
  require_arg "${REMOTE_WORK_ROOT}" "remote_work_root for machine ${MACHINE}"
  require_arg "${RUNS_ROOT}" "runs_root for machine ${MACHINE}"
  require_arg "${SCHEDULER}" "scheduler for machine ${MACHINE}"

  case "${EXECUTION_POLICY}" in
    profile_controlled|scheduler_only)
      ;;
    *)
      die "unsupported execution_policy for machine ${MACHINE}: ${EXECUTION_POLICY}"
      ;;
  esac
}

require_scheduler() {
  local expected="$1"
  if [[ "${SCHEDULER}" != "${expected}" ]]; then
    die "machine ${MACHINE} has scheduler=${SCHEDULER}; this script requires scheduler=${expected}"
  fi
}

require_arg() {
  local value="$1"
  local name="$2"
  if [[ -z "${value}" ]]; then
    die "missing required argument: ${name}"
  fi
}

shell_quote() {
  printf "%q" "$1"
}

ensure_project_relpath() {
  local project="$1"
  require_arg "${project}" "project"
  if [[ "${project}" = /* ]]; then
    die "project must be relative to ${REMOTE_WORK_ROOT}, got absolute path: ${project}"
  fi
  if [[ "${project}" == *".."* ]]; then
    die "project must not contain '..': ${project}"
  fi
}

project_path() {
  local project="$1"
  ensure_project_relpath "${project}"
  printf "%s/%s" "${REMOTE_WORK_ROOT}" "${project}"
}

ssh_login() {
  ssh "${SSH_ALIAS}" "$@"
}

ssh_login_script() {
  ssh "${SSH_ALIAS}" 'bash -s'
}

enforce_target_access_policy() {
  local target="$1"
  require_arg "${target}" "target"

  if [[ "${EXECUTION_POLICY}" == "scheduler_only" && "${target}" != "${LOGIN_NODE}" ]]; then
    die "machine ${MACHINE} is scheduler_only; refusing direct SSH to ${target}; submit with sbatch or request an interactive allocation with srun from ${LOGIN_NODE}"
  fi
}

ssh_target() {
  local target="$1"
  local remote_cmd="$2"
  local quoted_target
  local quoted_remote_cmd

  enforce_target_access_policy "${target}"

  if [[ "${target}" == "${LOGIN_NODE}" ]]; then
    ssh "${SSH_ALIAS}" "${remote_cmd}"
    return
  fi

  quoted_target="$(shell_quote "${target}")"
  quoted_remote_cmd="$(shell_quote "${remote_cmd}")"
  ssh "${SSH_ALIAS}" "ssh ${quoted_target} ${quoted_remote_cmd}"
}

ssh_target_script() {
  local target="$1"
  local quoted_target
  enforce_target_access_policy "${target}"

  if [[ "${target}" == "${LOGIN_NODE}" ]]; then
    ssh "${SSH_ALIAS}" 'bash -s'
    return
  fi

  quoted_target="$(shell_quote "${target}")"
  ssh "${SSH_ALIAS}" "ssh ${quoted_target} bash -s"
}

is_forbidden_business_target() {
  local target="$1"
  local item
  local -a items

  IFS=',' read -ra items <<<"${FORBIDDEN_BUSINESS_TARGETS}"
  for item in "${items[@]}"; do
    if [[ "${target}" == "${item}" ]]; then
      return 0
    fi
  done

  return 1
}

print_kv() {
  local key="$1"
  local value="$2"
  printf "%-14s %s\n" "${key}:" "${value}"
}
