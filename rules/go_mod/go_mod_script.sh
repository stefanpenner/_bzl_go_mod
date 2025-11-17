#!/usr/bin/env bash
# Script to assemble a Go module archive with source files
# Usage: assemble_go_mod.sh [src_file importpath ...]
# 
# Environment variables:
#   OUT_DIR         - Output directory path
#   GO_MOD          - Path to go.mod file
#   GO_SUM          - Path to go.sum file
#   MODULE_PATH     - Go module import path (e.g., example.com/demo)

set -e

# Validate required environment variables
: "${OUT_DIR:?OUT_DIR environment variable is required}"
: "${GO_MOD:?GO_MOD environment variable is required}"
: "${GO_SUM:?GO_SUM environment variable is required}"
: "${MODULE_PATH:?MODULE_PATH environment variable is required}"

# Copy go.mod and go.sum to module path location
cp "$GO_MOD" "$OUT_DIR/go.mod"
cp "$GO_SUM" "$OUT_DIR/go.sum"

# Copy all source files, maintaining import path structure
while [ $# -gt 0 ]; do
    src_file="$1"
    importpath="$2"
    shift 2

    # strip MODULE_PATH prefix from importpath
    rel_path="${importpath#"$MODULE_PATH"/}"
    target_dir="$OUT_DIR/$rel_path"
    mkdir -p "$target_dir"
    cp "$src_file" "$target_dir/$(basename "$src_file")" || echo "Failed to copy $src_file to $target_dir"
done
