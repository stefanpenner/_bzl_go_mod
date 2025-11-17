#!/bin/bash
set -euo pipefail

# Test script for go_mod rule
# Takes the go_mod target output directory as input

GO_MOD_DIR="$1"
cd "$GO_MOD_DIR"

echo "test root: $(pwd)"

# Assert go.mod exists
[ -f "go.mod" ] || { echo "ERROR: go.mod not found in $(pwd)"; exit 1; }

# Assert go.sum exists
[ -f "go.sum" ] || { echo "ERROR: go.sum not found in $(pwd)"; exit 1; }

# Assert utils/utils.go exists
[ -f "utils/utils.go" ] || { echo "ERROR: utils/utils.go not found"; exit 1; }

# Assert models/user.go exists
[ -f "models/user.go" ] || { echo "ERROR: models/user.go not found"; exit 1; }

# Assert cmd/app/main.go exists
[ -f "cmd/app/main.go" ] || { echo "ERROR: cmd/app/main.go not found"; exit 1; }

# Assert embedfs files exist (Go source and embedded data)
[ -f "embedfs/embedfs.go" ] || { echo "ERROR: embedfs/embedfs.go not found"; exit 1; }
[ -f "embedfs/data.txt" ] || { echo "ERROR: embedfs/data.txt not found"; exit 1; }

# Assert cdeps CGo-related files exist (.go, .c, and .h)
[ -f "cdeps/foo.go" ] || { echo "ERROR: cdeps/foo.go not found"; exit 1; }
[ -f "cdeps/foo.c" ] || { echo "ERROR: cdeps/foo.c not found"; exit 1; }
[ -f "cdeps/foo.h" ] || { echo "ERROR: cdeps/foo.h not found"; exit 1; }

# Assert no external dependencies are included
[ ! -d "gazelle++go_deps+com_github_google_uuid" ] || { echo "ERROR: External dependencies should not be included"; exit 1; }

# Assert go.mod contains expected module name
grep -q "module github.com/stefanpenner/bazel_go_mod" "go.mod" || { echo "ERROR: go.mod does not contain expected module name"; exit 1; }

# Assert go.mod contains expected Go version
grep -q "go 1.25" "go.mod" || { echo "ERROR: go.mod does not contain expected Go version"; exit 1; }

# Assert go.mod contains expected uuid dependency
grep -q "github.com/google/uuid" "go.mod" || { echo "ERROR: go.mod does not contain expected uuid dependency"; exit 1; }

# Assert utils.go contains expected package declaration
grep -q "package utils" "utils/utils.go" || { echo "ERROR: utils.go does not contain expected package declaration"; exit 1; }

# Assert user.go contains expected package declaration
grep -q "package models" "models/user.go" || { echo "ERROR: user.go does not contain expected package declaration"; exit 1; }

# Assert main.go contains expected package declaration
grep -q "package main" "cmd/app/main.go" || { echo "ERROR: main.go does not contain expected package declaration"; exit 1; }

echo "All tests passed!"
