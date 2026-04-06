#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
PLIST_PATH="${ROOT_DIR}/RightLayout/Info.plist"
VERSION_FILE="${ROOT_DIR}/VERSION"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

set_plist_value() {
  local key="$1"
  local value="$2"

  if "${PLIST_BUDDY}" -c "Print :${key}" "${PLIST_PATH}" >/dev/null 2>&1; then
    "${PLIST_BUDDY}" -c "Set :${key} ${value}" "${PLIST_PATH}"
  else
    "${PLIST_BUDDY}" -c "Add :${key} string ${value}" "${PLIST_PATH}"
  fi
}

[[ -n "${VERSION}" ]] || die "sync_version.sh requires a version argument"
[[ -f "${PLIST_PATH}" ]] || die "Info.plist not found at ${PLIST_PATH}"

printf "%s\n" "${VERSION}" > "${VERSION_FILE}"
set_plist_value "CFBundleShortVersionString" "${VERSION}"
set_plist_value "CFBundleVersion" "${VERSION}"

printf "Synced version to %s and %s: %s\n" "${VERSION_FILE}" "${PLIST_PATH}" "${VERSION}"
