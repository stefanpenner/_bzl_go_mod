#!/usr/bin/env bash
set -euo pipefail

# Construct the path to gazelle_go_mod from runfiles
# The all_files filegroup makes all files available under the standard runfiles structure
SRC_ROOT="${RUNFILES_DIR}/${TEST_WORKSPACE}/testdata/gazelle_go_mod"
echo "SRC_ROOT: ${SRC_ROOT}"
# Copy the entire gazelle_go_mod directory into TEST_TMPDIR, following symlinks
cp -RL "${SRC_ROOT}/" "${TEST_TMPDIR}/workspace"
chmod -R +w "${TEST_TMPDIR}/workspace"

# Resolve GAZELLE_BIN to absolute path and run gazelle in the workspace directory
GAZELLE_BIN="$(realpath "${GAZELLE_BIN}")"

# let's step into the workspace directory and run gazelle
cd "${TEST_TMPDIR}/workspace"
echo "Running gazelle: ${GAZELLE_BIN} -repo_root=. in: $(pwd)"

"${GAZELLE_BIN}" -repo_root="." > "$TEST_TMPDIR/gazelle.log" 2>&1

# let's check the gazelle.log file
cat "$TEST_TMPDIR/gazelle.log"

# let's check the workspace directory
ls -la "${TEST_TMPDIR}/workspace"

# some assertions, just making sure the basic files are present

[ -f "${TEST_TMPDIR}/workspace/mod1/go.mod" ] || { echo "ERROR: go.mod not found in ${TEST_TMPDIR}/workspace/mod1"; exit 1; }
[ -f "${TEST_TMPDIR}/workspace/mod1/BUILD.bazel" ] || { echo "ERROR: BUILD.bazel not found in ${TEST_TMPDIR}/workspace/mod1/BUILD.bazel"; exit 1; }
[ -f "${TEST_TMPDIR}/workspace/mod2/go.mod" ] || { echo "ERROR: go.mod not found in ${TEST_TMPDIR}/workspace/mod2"; exit 1; }
[ -f "${TEST_TMPDIR}/workspace/mod2/BUILD.bazel" ] || { echo "ERROR: BUILD.bazel not found in ${TEST_TMPDIR}/workspace/mod2/BUILD.bazel"; exit 1; }

# now let's assert the input BUILD.bazel files are correct

if grep -Fxq 'go_library(' "${SRC_ROOT}/mod1/BUILD.bazel"; then
  echo "ERROR: go_library should NOT YET be found in ${SRC_ROOT}/mod1/BUILD.bazel but was found"
  cat "${SRC_ROOT}/mod1/BUILD.bazel"
  exit 1
fi