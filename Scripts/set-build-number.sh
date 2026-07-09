#!/bin/bash
set -euo pipefail

# CFBundleVersion: date + time at build (e.g. 20260709_1600)
BUILD_NUMBER="$(date '+%Y%m%d_%H%M')"
INFOPLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [[ ! -f "${INFOPLIST}" ]]; then
  echo "warning: Info.plist not found at ${INFOPLIST}" >&2
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${INFOPLIST}"
echo "Set CFBundleVersion to ${BUILD_NUMBER}"
