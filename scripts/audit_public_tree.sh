#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRIVATE_DIR="${REMOTE_HPC_OPERATOR_CONFIG_DIR:-${REPO_ROOT}/references/machines/local}"
PRIVATE_DENYLIST="${PRIVATE_DIR}/private-patterns.txt"
MODE="${1:---tracked}"
FAILURES=0

usage() {
  cat <<'EOF'
Usage:
  audit_public_tree.sh [--staged|--tracked]

Description:
  Audit Git-index content for private machine configuration, credentials,
  infrastructure paths, and literals from the optional private denylist.

Modes:
  --staged  Scan files added, copied, modified, or renamed in the staged diff.
  --tracked Scan every file currently present in the Git index.
EOF
}

report_failure() {
  local path="$1"
  local reason="$2"
  printf 'BLOCKED: %s (%s)\n' "${path}" "${reason}" >&2
  FAILURES=$((FAILURES + 1))
}

case "${MODE}" in
  --staged|--tracked)
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    printf 'ERROR: unknown mode: %s\n' "${MODE}" >&2
    usage >&2
    exit 2
    ;;
esac

if ! git -C "${REPO_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'ERROR: not a Git repository: %s\n' "${REPO_ROOT}" >&2
  exit 2
fi

FILES_LIST="$(mktemp)"
BLOB_FILE="$(mktemp)"
trap 'rm -f "${FILES_LIST}" "${BLOB_FILE}"' EXIT

if [[ "${MODE}" == "--staged" ]]; then
  git -C "${REPO_ROOT}" diff --cached --name-only --diff-filter=ACMR -z > "${FILES_LIST}"
else
  git -C "${REPO_ROOT}" ls-files -z > "${FILES_LIST}"
fi

while IFS= read -r -d '' path; do
  case "${path}" in
    references/machines/local|references/machines/local/*)
      report_failure "${path}" "private machine configuration must never be tracked"
      continue
      ;;
  esac

  case "${path}" in
    .env|.env.*|*.key|*.pem|*.p12|*.pfx|*.crt|*.cer|*.pub|id_rsa*|id_ed25519*)
      if [[ "${path}" != ".env.example" ]]; then
        report_failure "${path}" "sensitive filename"
        continue
      fi
      ;;
  esac

  if ! git -C "${REPO_ROOT}" show ":${path}" > "${BLOB_FILE}" 2>/dev/null; then
    continue
  fi

  if [[ -f "${PRIVATE_DENYLIST}" ]]; then
    while IFS= read -r literal || [[ -n "${literal}" ]]; do
      [[ -z "${literal}" || "${literal}" == \#* ]] && continue
      if LC_ALL=C grep -F -q -- "${literal}" "${BLOB_FILE}"; then
        report_failure "${path}" "matches private denylist"
        break
      fi
    done < "${PRIVATE_DENYLIST}"
  fi

  if [[ "${path}" == "scripts/audit_public_tree.sh" ]]; then
    continue
  fi

  if LC_ALL=C grep -E -q -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' "${BLOB_FILE}"; then
    report_failure "${path}" "contains a private-key header"
  fi

  if LC_ALL=C grep -E -i -q -- '(password|passwd|token|secret|api[_-]?key|client[_-]?secret)[[:space:]]*[:=][[:space:]]*['"'"'"]?[A-Za-z0-9_./+=-]{8,}' "${BLOB_FILE}"; then
    report_failure "${path}" "contains a credential-like assignment"
  fi

  if LC_ALL=C grep -E -q -- '/(gpfs|lustre|storage|scratch)/[A-Za-z0-9._/-]+' "${BLOB_FILE}"; then
    report_failure "${path}" "contains a concrete cluster filesystem path"
  fi

  if LC_ALL=C grep -E -- '(Username|Login host alias|Login node hostname|SSH access):' "${BLOB_FILE}" \
      | LC_ALL=C grep -E -v -q -- '<[A-Za-z0-9_ -]+>'; then
    report_failure "${path}" "contains a concrete machine-profile identity field"
  fi
done < "${FILES_LIST}"

if [[ "${FAILURES}" -ne 0 ]]; then
  printf 'Public-tree audit failed with %d blocked file(s).\n' "${FAILURES}" >&2
  exit 1
fi

printf 'Public-tree audit passed (%s).\n' "${MODE}"
