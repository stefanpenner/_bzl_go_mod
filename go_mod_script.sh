#!/bin/bash
set -euo pipefail

OUTPUT_DIR="$1"
GO_MOD="$2"
GO_SUM="$3"
shift 3

mkdir -p "$OUTPUT_DIR"

# Copy go.mod and go.sum
cp "$GO_MOD" "$OUTPUT_DIR/go.mod"
if [ "$GO_SUM" != "" ]; then
    cp "$GO_SUM" "$OUTPUT_DIR/go.sum"
fi

# Process each source file
# Files are passed as: file_path|short_path pairs
while [ $# -gt 0 ]; do
    file_pair="$1"
    shift
    
    file_path=$(echo "$file_pair" | cut -d'|' -f1)
    short_path=$(echo "$file_pair" | cut -d'|' -f2)
    
    # Use short_path to preserve package structure, but clean it up
    # Remove external repo prefixes and bazel-out paths
    clean_path=$(echo "$short_path" | sed 's|^external/[^/]*/||' | sed 's|^bazel-out/[^/]*/bin/||' | sed 's|^../||')
    
    dest_path="$OUTPUT_DIR/$clean_path"
    mkdir -p "$(dirname "$dest_path")"
    cp "$file_path" "$dest_path"
done

