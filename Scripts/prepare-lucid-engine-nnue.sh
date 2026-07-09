#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCE_DIR="$PROJECT_DIR/StockfishNNUE"

LUCID_NNUE_FILES=(
    "nn-1c0000000000.nnue"
    "nn-37f18f62d772.nnue"
)

LUCID_DOWNLOAD_URLS=(
    "https://tests.stockfishchess.org/api/nn/nn-1c0000000000.nnue"
    "https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue"
)

is_placeholder_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 0
    local size
    size=$(wc -c < "$file" | tr -d ' ')
    [[ "$size" -lt 1024 ]]
}

ensure_resource_file() {
    local name="$1"
    local url="$2"
    local destination="$RESOURCE_DIR/$name"

    mkdir -p "$RESOURCE_DIR"

    if ! is_placeholder_file "$destination"; then
        return 0
    fi

    echo "Downloading Stockfish NNUE file: $name"
    curl -fsSL "$url" -o "$destination"
}

for index in "${!LUCID_NNUE_FILES[@]}"; do
    ensure_resource_file "${LUCID_NNUE_FILES[$index]}" "${LUCID_DOWNLOAD_URLS[$index]}"
done

find_lucid_checkout() {
    if [[ -n "${DERIVED_DATA_DIR:-}" ]]; then
        local match
        match=$(find "$DERIVED_DATA_DIR" -path "*/SourcePackages/checkouts/lucid-engine/Sources/CStockfish/src/stockfish" -type d 2>/dev/null | head -n 1 || true)
        if [[ -n "$match" ]]; then
            echo "$match"
            return 0
        fi
    fi

    if [[ -n "${SRCROOT:-}" ]]; then
        local derived_root
        derived_root="$(cd "$SRCROOT/.." && pwd)"
        local match
        match=$(find "$derived_root" -path "*/SourcePackages/checkouts/lucid-engine/Sources/CStockfish/src/stockfish" -type d 2>/dev/null | head -n 1 || true)
        if [[ -n "$match" ]]; then
            echo "$match"
            return 0
        fi
    fi

    find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/checkouts/lucid-engine/Sources/CStockfish/src/stockfish" -type d 2>/dev/null | head -n 1
}

CHECKOUT_DIR="$(find_lucid_checkout || true)"
if [[ -z "$CHECKOUT_DIR" ]]; then
    echo "warning: LucidEngine checkout not found yet. NNUE files are cached in Resources for the next build."
    exit 0
fi

for name in "${LUCID_NNUE_FILES[@]}"; do
    chmod u+w "$CHECKOUT_DIR/$name" 2>/dev/null || true
    cp "$RESOURCE_DIR/$name" "$CHECKOUT_DIR/$name"
done

DERIVED_ROOT="$(cd "$CHECKOUT_DIR/../../../../../.." && pwd)"
if [[ -d "$DERIVED_ROOT/Build/Intermediates.noindex/LucidEngine.build" ]]; then
    rm -rf "$DERIVED_ROOT/Build/Intermediates.noindex/LucidEngine.build"
    echo "Cleared cached LucidEngine build artifacts so NNUE files are re-embedded."
fi

echo "Prepared LucidEngine NNUE files in $CHECKOUT_DIR"
