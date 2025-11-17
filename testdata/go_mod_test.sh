#!/bin/bash
set -euo pipefail

# Test script for go_mod rule
# Takes the go_mod target output directory as input

GO_MOD_DIR="$1"

# Assert go.mod exists
[ -f "$GO_MOD_DIR/go.mod" ] || { echo "ERROR: go.mod not found in $GO_MOD_DIR"; exit 1; }

# Assert go.sum exists
[ -f "$GO_MOD_DIR/go.sum" ] || { echo "ERROR: go.sum not found in $GO_MOD_DIR"; exit 1; }

# Assert utils/utils.go exists (try both with and without testdata prefix)
UTILS_FILE=""
[ -f "$GO_MOD_DIR/testdata/utils/utils.go" ] && UTILS_FILE="$GO_MOD_DIR/testdata/utils/utils.go"
[ -f "$GO_MOD_DIR/utils/utils.go" ] && UTILS_FILE="$GO_MOD_DIR/utils/utils.go"
[ -n "$UTILS_FILE" ] || { echo "ERROR: utils/utils.go not found"; exit 1; }

# Assert models/user.go exists (try both with and without testdata prefix)
MODELS_FILE=""
[ -f "$GO_MOD_DIR/testdata/models/user.go" ] && MODELS_FILE="$GO_MOD_DIR/testdata/models/user.go"
[ -f "$GO_MOD_DIR/models/user.go" ] && MODELS_FILE="$GO_MOD_DIR/models/user.go"
[ -n "$MODELS_FILE" ] || { echo "ERROR: models/user.go not found"; exit 1; }

# Assert cmd/app/main.go exists (try both with and without testdata prefix)
APP_FILE=""
[ -f "$GO_MOD_DIR/testdata/cmd/app/main.go" ] && APP_FILE="$GO_MOD_DIR/testdata/cmd/app/main.go"
[ -f "$GO_MOD_DIR/cmd/app/main.go" ] && APP_FILE="$GO_MOD_DIR/cmd/app/main.go"
[ -n "$APP_FILE" ] || { echo "ERROR: cmd/app/main.go not found"; exit 1; }

# Assert go.mod contains expected module name
grep -q "module github.com/stefanpenner/bazel_go_mod" "$GO_MOD_DIR/go.mod" || { echo "ERROR: go.mod does not contain expected module name"; exit 1; }

# Assert go.mod contains expected Go version
grep -q "go 1.25" "$GO_MOD_DIR/go.mod" || { echo "ERROR: go.mod does not contain expected Go version"; exit 1; }

# Assert go.mod contains expected uuid dependency
grep -q "github.com/google/uuid" "$GO_MOD_DIR/go.mod" || { echo "ERROR: go.mod does not contain expected uuid dependency"; exit 1; }

# Assert utils.go contains expected package declaration
grep -q "package utils" "$UTILS_FILE" || { echo "ERROR: utils.go does not contain expected package declaration"; exit 1; }

# Assert user.go contains expected package declaration
grep -q "package models" "$MODELS_FILE" || { echo "ERROR: user.go does not contain expected package declaration"; exit 1; }

# Assert main.go contains expected package declaration
grep -q "package main" "$APP_FILE" || { echo "ERROR: main.go does not contain expected package declaration"; exit 1; }

echo "All tests passed!"
