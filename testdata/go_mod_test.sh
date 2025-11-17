#!/bin/bash
set -euo pipefail

# Test script for go_mod rule
# Takes the go_mod target output directory as input

GO_MOD_DIR="$1"

# Files are now organized under the module path
MODULE_BASE="$GO_MOD_DIR/github.com/stefanpenner/bazel_go_mod"

# Assert go.mod exists
[ -f "$MODULE_BASE/go.mod" ] || { echo "ERROR: go.mod not found in $MODULE_BASE"; exit 1; }

# Assert go.sum exists
[ -f "$MODULE_BASE/go.sum" ] || { echo "ERROR: go.sum not found in $MODULE_BASE"; exit 1; }

# Assert utils/utils.go exists
[ -f "$MODULE_BASE/utils/utils.go" ] || { echo "ERROR: utils/utils.go not found"; exit 1; }

# Assert models/user.go exists
[ -f "$MODULE_BASE/models/user.go" ] || { echo "ERROR: models/user.go not found"; exit 1; }

# Assert cmd/app/main.go exists
[ -f "$MODULE_BASE/cmd/app/main.go" ] || { echo "ERROR: cmd/app/main.go not found"; exit 1; }

# Assert no external dependencies are included
[ ! -d "$GO_MOD_DIR/gazelle++go_deps+com_github_google_uuid" ] || { echo "ERROR: External dependencies should not be included"; exit 1; }

# Assert go.mod contains expected module name
grep -q "module github.com/stefanpenner/bazel_go_mod" "$MODULE_BASE/go.mod" || { echo "ERROR: go.mod does not contain expected module name"; exit 1; }

# Assert go.mod contains expected Go version
grep -q "go 1.25" "$MODULE_BASE/go.mod" || { echo "ERROR: go.mod does not contain expected Go version"; exit 1; }

# Assert go.mod contains expected uuid dependency
grep -q "github.com/google/uuid" "$MODULE_BASE/go.mod" || { echo "ERROR: go.mod does not contain expected uuid dependency"; exit 1; }

# Assert utils.go contains expected package declaration
grep -q "package utils" "$MODULE_BASE/utils/utils.go" || { echo "ERROR: utils.go does not contain expected package declaration"; exit 1; }

# Assert user.go contains expected package declaration
grep -q "package models" "$MODULE_BASE/models/user.go" || { echo "ERROR: user.go does not contain expected package declaration"; exit 1; }

# Assert main.go contains expected package declaration
grep -q "package main" "$MODULE_BASE/cmd/app/main.go" || { echo "ERROR: main.go does not contain expected package declaration"; exit 1; }

echo "All tests passed!"
