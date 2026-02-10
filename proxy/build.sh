#!/usr/bin/env bash
set -euo pipefail

echo "Building Agent..."

if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed"
    exit 1
fi

BIN_DIR="bin"
BIN_PATH="${BIN_DIR}/socks-proxy"

if [ -f "$BIN_PATH" ]; then
    rm -f "$BIN_PATH"
    echo "Removed old build"
fi

echo "Installing dependencies..."
go mod tidy
if [ $? -ne 0 ]; then
    echo "Error: Failed to install dependencies"
    exit 1
fi

echo "Building application (host)..."
mkdir -p "$BIN_DIR"
go build -o "$BIN_PATH" main.go
if [ $? -ne 0 ]; then
    echo "Error: Build failed"
    exit 1
fi

TARGETS=(
    "darwin/arm64"
    "darwin/amd64"
    "linux/amd64"
    "linux/arm64"
    "windows/amd64"
)

echo "Building cross-platform binaries..."
for t in "${TARGETS[@]}"; do
    os="${t%/*}"
    arch="${t#*/}"
    ext=""
    [[ "$os" == "windows" ]] && ext=".exe"
    out="${BIN_DIR}/socks-proxy-${os}-${arch}${ext}"
    GOOS="$os" GOARCH="$arch" go build -o "$out" main.go
done

echo "Build successful!"
