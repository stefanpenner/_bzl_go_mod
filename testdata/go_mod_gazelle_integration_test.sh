#!/usr/bin/env bash
set -euo pipefail

# Construct the path to gazelle_go_mod from runfiles
# The all_files filegroup makes all files available under the standard runfiles structure
SRC_ROOT="${RUNFILES_DIR}/${TEST_WORKSPACE}/testdata/gazelle_go_mod"

# Copy the entire gazelle_go_mod directory into TEST_TMPDIR
cp -R "${SRC_ROOT}/" "${TEST_TMPDIR}/workspace"

echo "WORKSPACE: $TEST_TMPDIR/workspace"