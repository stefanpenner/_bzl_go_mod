#!/usr/bin/env bash
set -euo pipefail

# this is the testdata that we will run against.
# Think of it like fixture data
SRC_ROOT="${RUNFILES_DIR}/${TEST_WORKSPACE}/testdata/gazelle_go_mod"

# Copy the entire gazelle_go_mod directory into TEST_TMPDIR, following symlinks
cp -RL "${SRC_ROOT}/" "${TEST_TMPDIR}/workspace"
chmod -R +w "${TEST_TMPDIR}/workspace"

# Resolve GAZELLE_BIN to absolute paths
GAZELLE_BIN="$(realpath "${GAZELLE_BIN}")"

assert_file_exists() {
  local file="$1"

  [ -f "$file" ] || {
    echo "Error: expected $file, but it did not exist"
    exit 1
  }
}

assert_file_contains() {
  local content="$1"
  local file="$2"

  assert_file_exists "$file"

  if ! grep -q "$content" "$file"; then
    echo "ERROR: expected to find '$content' rather we found:"
    echo "====== file: $file"
    echo "$(cat $file)"
    echo "======"
    exit 1
  fi
}

assert_file_does_not_contain() {
  local content="$1"
  local file="$2"

  assert_file_exists "$file"

  if grep -q "$content" "$file"; then
    echo "ERROR: '$content' should NOT YET be found in:"
    echo "====== file: $file"
    echo "$(cat $file)"
    echo "======"
    exit 1
  fi
}

# let's step into the workspace directory and run gazelle
cd "${TEST_TMPDIR}/workspace"

# some assertions, just making sure the basic files are present

assert_file_exists "${TEST_TMPDIR}/workspace/mod1/go.mod"
assert_file_exists "${TEST_TMPDIR}/workspace/mod2/go.mod"
assert_file_exists "${TEST_TMPDIR}/workspace/mod1/BUILD.bazel"
assert_file_exists "${TEST_TMPDIR}/workspace/mod2/BUILD.bazel"

# now let's assert the BUILD.bazel files are correct, and have not yet had gazelle run on them
# no go_library yet
assert_file_does_not_contain 'go_library(' "$TEST_TMPDIR/workspace/mod1/pkg1/BUILD.bazel"
assert_file_does_not_contain 'go_library(' "$TEST_TMPDIR/workspace/mod1/pkg2/BUILD.bazel"
assert_file_does_not_contain 'go_library(' "$TEST_TMPDIR/workspace/mod2/pkg3/BUILD.bazel"

# no go_mod yet
assert_file_does_not_contain 'go_mod(' "$TEST_TMPDIR/workspace/mod1/BUILD.bazel"
assert_file_does_not_contain 'go_mod(' "$TEST_TMPDIR/workspace/mod2/BUILD.bazel"
assert_file_does_not_contain ':mod1' "$TEST_TMPDIR/workspace/mod2/BUILD.bazel"

echo "workspace under test: $(pwd)"
echo "Running gazelle: ${GAZELLE_BIN} -repo_root=. in: $(pwd)"
# Now let's run gazelle
"${GAZELLE_BIN}" -repo_root="." >"$TEST_TMPDIR/gazelle.log" 2>&1 || {
  echo "ERROR: gazelle failed"
  cat "$TEST_TMPDIR/gazelle.log"
  exit 1
}

# now lets assert the files look right
# there should be go_library's
assert_file_contains 'go_library(' "$TEST_TMPDIR/workspace/mod1/pkg1/BUILD.bazel"
assert_file_contains 'go_library(' "$TEST_TMPDIR/workspace/mod1/pkg2/BUILD.bazel"
assert_file_contains 'go_library(' "$TEST_TMPDIR/workspace/mod2/pkg3/BUILD.bazel"

# there should be go_mod's
assert_file_contains 'go_mod(' "$TEST_TMPDIR/workspace/mod1/BUILD.bazel"
assert_file_contains 'go_mod(' "$TEST_TMPDIR/workspace/mod2/BUILD.bazel"

# there should be no go_mods
assert_file_does_not_contain 'go_mod(' "$TEST_TMPDIR/workspace/mod1/pkg1/BUILD.bazel"
assert_file_does_not_contain 'go_mod(' "$TEST_TMPDIR/workspace/mod1/pkg2/BUILD.bazel"
assert_file_does_not_contain 'go_mod(' "$TEST_TMPDIR/workspace/mod2/pkg3/BUILD.bazel"

# there should be deps in mod1/BUILD.bazel's go_mod
assert_file_contains ':mod1' "$TEST_TMPDIR/workspace/mod1/BUILD.bazel"
assert_file_contains '//pkg1' "$TEST_TMPDIR/workspace/mod1/BUILD.bazel"
assert_file_contains '//pkg2' "$TEST_TMPDIR/workspace/mod1/BUILD.bazel"

# there should be deps in mod2/BUILD.bazel's go_mod
assert_file_contains '//pkg3' "$TEST_TMPDIR/workspace/mod2/BUILD.bazel"
