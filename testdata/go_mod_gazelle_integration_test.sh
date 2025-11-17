#!/usr/bin/env bash
set -euo pipefail

# Locate the test workspace copy of the gazelle_go_mod testdata.
SRC_ROOT="${RUNFILES_DIR}/${TEST_WORKSPACE}/testdata/gazelle_go_mod"

if [[ ! -d "$SRC_ROOT" ]]; then
  echo "Expected testdata directory not found at $SRC_ROOT" >&2
  exit 1
fi

WORKDIR="${TEST_TMPDIR}/go_mod_gazelle_integration"
mkdir -p "${WORKDIR}"

cp -R "${SRC_ROOT}/" "${WORKDIR}/workspace"
REPO_ROOT="${WORKDIR}/workspace"

GAZELLE_BIN="$(realpath $GAZELLE_BIN)"
cd "${REPO_ROOT}"

# Run gazelle in fix mode over the copied repo.
"${GAZELLE_BIN}" -repo_root="."

echo "CWD: $(pwd)"

# Verify that exactly one go_mod rule is generated for each go.mod-containing
# directory, that module_path is derived from the go.mod contents, and that
# go_mod rules depend on a go_library in the same package.

mod1_build="${REPO_ROOT}/mod1/BUILD.bazel"
mod2_build="${REPO_ROOT}/mod2/BUILD.bazel"

for build in "$mod1_build" "$mod2_build"; do
  if [[ ! -f "$build" ]]; then
    echo "Expected BUILD.bazel at $build" >&2
    exit 1
  fi
done

# There should be exactly one go_mod rule per file.
if [[ "$(grep -c 'go_mod(' "$mod1_build" || true)" -ne 1 ]]; then
  echo "Expected exactly one go_mod rule in $mod1_build" >&2
  exit 1
fi
if [[ "$(grep -c 'go_mod(' "$mod2_build" || true)" -ne 1 ]]; then
  echo "Expected exactly one go_mod rule in $mod2_build" >&2
  exit 1
fi

# Check module_path and go_mod attributes.
grep -q 'module_path = "example.com/mod1"' "$mod1_build" || {
  echo "module_path for mod1 not set correctly" >&2
  exit 1
}
grep -q 'go_mod = ":go.mod"' "$mod1_build" || {
  echo "go_mod attr for mod1 not set correctly" >&2
  exit 1
}

grep -q 'module_path = "example.com/mod2"' "$mod2_build" || {
  echo "module_path for mod2 not set correctly" >&2
  exit 1
}
grep -q 'go_mod = ":go.mod"' "$mod2_build" || {
  echo "go_mod attr for mod2 not set correctly" >&2
  exit 1
}

# Ensure that Gazelle generated a go_library in each module root and that the
# corresponding go_mod rule depends on at least one local target (typically
# that go_library). This keeps the check simple and readable while still
# verifying the intended wiring.
for build in "$mod1_build" "$mod2_build"; do
  # go_library must exist in the module root.
  if ! grep -q 'go_library(' "$build"; then
    echo "Expected go_library rule in $build but none was found. File contents:" >&2
    sed -n '1,80p' "$build" >&2 || true
    exit 1
  fi

  # The go_mod rule should have a deps entry that references a local label.
  # We don't care about the exact name here, only that it depends on some
  # local target in this package.
  if ! grep -A10 '^go_mod(' "$build" | grep -q '":'; then
    echo "go_mod rule in $build does not appear to depend on any local label (e.g. :lib). go_mod block:" >&2
    grep -n -A10 -B2 '^go_mod(' "$build" >&2 || {
      echo "No go_mod rule block could be located in $build" >&2
    }
    exit 1
  fi
done

# Ensure no go_mod rules are generated in sub-packages that do not contain
# a go.mod file.
if [[ -f "${REPO_ROOT}/mod1/pkg1/BUILD.bazel" ]]; then
  if grep -q 'go_mod(' "${REPO_ROOT}/mod1/pkg1/BUILD.bazel"; then
    echo "Unexpected go_mod rule in mod1/pkg1" >&2
    exit 1
  fi
fi

if [[ -f "${REPO_ROOT}/mod1/pkg2/BUILD.bazel" ]]; then
  if grep -q 'go_mod(' "${REPO_ROOT}/mod1/pkg2/BUILD.bazel"; then
    echo "Unexpected go_mod rule in mod1/pkg2" >&2
    exit 1
  fi
fi

if [[ -f "${REPO_ROOT}/mod2/pkg3/BUILD.bazel" ]]; then
  if grep -q 'go_mod(' "${REPO_ROOT}/mod2/pkg3/BUILD.bazel"; then
    echo "Unexpected go_mod rule in mod2/pkg3" >&2
    exit 1
  fi
fi

echo "go_mod Gazelle integration test passed"


