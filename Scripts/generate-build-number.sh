#!/bin/bash
set -euo pipefail

# App Store requires CFBundleVersion as 1–3 period-separated integers.
BUILD_NUMBER="$(date '+%Y%m%d.%H%M')"
OUTPUT="${SRCROOT}/BuildNumber.xcconfig"

cat > "${OUTPUT}" <<EOF
// Generated at build time — do not edit.
CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}
EOF

echo "Generated CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}"
