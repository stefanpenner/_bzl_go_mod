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

# Create output directory and module path subdirectory
mkdir -p "$OUT_DIR/$MODULE_PATH"

# Copy go.mod and go.sum to module path location
cp "$GO_MOD" "$OUT_DIR/$MODULE_PATH/go.mod"
cp "$GO_SUM" "$OUT_DIR/$MODULE_PATH/go.sum"

# Copy all source files, maintaining import path structure
while [ $# -gt 0 ]; do
    src_file="$1"
    importpath="$2"
    shift 2
    
    target_dir="$OUT_DIR/$importpath"
    mkdir -p "$target_dir"
    cp "$src_file" "$target_dir/$(basename "$src_file")"
done
