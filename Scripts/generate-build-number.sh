#!/bin/bash
set -euo pipefail

BUILD_NUMBER="$(date '+%Y%m%d_%H%M')"
OUTPUT="${SRCROOT}/BuildNumber.xcconfig"

cat > "${OUTPUT}" <<EOF
// Generated at build time — do not edit.
CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}
EOF

echo "Generated CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}"
