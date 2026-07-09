#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCE_DIR="$PROJECT_DIR/StockfishNNUE"

download_if_missing() {
    local name="$1"
    local url="$2"
    local destination="$RESOURCE_DIR/$name"

    mkdir -p "$RESOURCE_DIR"

    if [[ -f "$destination" ]] && [[ "$(wc -c < "$destination" | tr -d ' ')" -gt 1024 ]]; then
        return 0
    fi

    echo "Downloading $name..."
    curl -fsSL "$url" -o "$destination"
}

download_if_missing "nn-37f18f62d772.nnue" "https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue"
download_if_missing "nn-1c0000000000.nnue" "https://tests.stockfishchess.org/api/nn/nn-1c0000000000.nnue"

echo "Stockfish NNUE files ready in $RESOURCE_DIR"
