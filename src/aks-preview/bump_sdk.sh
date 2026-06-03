#!/usr/bin/env bash
###############################################################################
# bump_sdk.sh — Automate SDK bump for the aks-preview extension.
#
# Usage:
#   ./bump_sdk.sh \
#       --old-api   2026-01-02-preview \
#       --new-api   2026-02-02-preview \
#       --cli-repo  /path/to/local/azure-cli \
#       --spec-repo /path/to/local/azure-rest-api-specs \
#       --sdk-repo  /path/to/local/azure-sdk-for-python
#
# The extension version (--old-ver / --new-ver) is auto-detected from
# setup.py if not specified. The next patch version is computed by
# incrementing the last numeric segment (e.g. 20.0.0b1 → 20.0.0b2).
#
# Repo handling:
#   - cli-repo:  Must be clean (no local changes). Checks out dev and pulls
#                latest. Left on dev afterward (not restored).
#   - spec-repo: Pulls latest main, modifies readme.md default tag for SDK
#                generation. Restored to original state on exit.
#   - sdk-repo:  Pulls latest main for SDK generation. Restored to original
#                state on exit.
#
# Prerequisites:
#   - Python 3.9+, Node.js >= 18 (with npm)
#   - azdev:       pip install azdev
###############################################################################
set -euo pipefail

# ──────────────────────────── Self-relocate to /tmp ──────────────────────
# The script lives on a tooling branch (e.g. fuming/sdk-auto) but creates a
# new feature branch off main. To survive the branch switch, copy ourselves
# to /tmp and re-exec from there, forwarding all arguments.  We also capture
# EXT_ROOT *before* the branch switch so paths stay valid.
if [[ "${BUMP_SDK_RELOCATED:-}" != "1" ]]; then
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    TMP_SCRIPT="/tmp/bump_sdk_$$.sh"
    cp "${SELF}" "${TMP_SCRIPT}"
    chmod +x "${TMP_SCRIPT}"
    # Pass the resolved EXT_ROOT so the /tmp copy doesn't need to derive it
    export BUMP_SDK_RELOCATED=1
    export BUMP_SDK_EXT_ROOT="$(cd "$(dirname "$0")" && pwd)"
    exec "${TMP_SCRIPT}" "$@"
fi

# ──────────────────────────── Parse arguments ────────────────────────────
OLD_API=""
NEW_API=""
OLD_VER=""
NEW_VER=""
CLI_REPO=""
SPEC_REPO=""
SDK_REPO=""
SKIP_SDK_GEN=false
SKIP_TESTS=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Required:
  --old-api   <version>   Current API version  (e.g. 2026-01-02-preview)
  --new-api   <version>   Target  API version  (e.g. 2026-02-02-preview)
  --cli-repo  <path>      Local azure-cli repo
  --spec-repo <path>      Local azure-rest-api-specs repo
  --sdk-repo  <path>      Local azure-sdk-for-python repo

Optional:
  --old-ver   <version>   Current extension ver (auto-detected from setup.py)
  --new-ver   <version>   Target  extension ver (auto-incremented from old-ver)
  --skip-sdk-gen           Skip Step 1 (SDK generation)
  --skip-tests             Skip Step 5 (test run)
  -h, --help               Show this help
EOF
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --old-api)       OLD_API="$2";   shift 2 ;;
        --new-api)       NEW_API="$2";   shift 2 ;;
        --old-ver)       OLD_VER="$2";   shift 2 ;;
        --new-ver)       NEW_VER="$2";   shift 2 ;;
        --cli-repo)      CLI_REPO="$2";  shift 2 ;;
        --spec-repo)     SPEC_REPO="$2"; shift 2 ;;
        --sdk-repo)      SDK_REPO="$2";  shift 2 ;;
        --skip-sdk-gen)  SKIP_SDK_GEN=true; shift ;;
        --skip-tests)    SKIP_TESTS=true;   shift ;;
        -h|--help)       usage 0 ;;
        *)               echo "Unknown option: $1"; usage 1 ;;
    esac
done

# Validate required args
for var_name in OLD_API NEW_API CLI_REPO SPEC_REPO SDK_REPO; do
    eval val=\$$var_name
    if [[ -z "$val" ]]; then
        echo "ERROR: --$(echo "$var_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]') is required."
        usage 1
    fi
done

# ──────────────────────────── Derived paths ──────────────────────────────
# Use the EXT_ROOT captured before relocation (points to the real repo path)
EXT_ROOT="${BUMP_SDK_EXT_ROOT}"
REPO_ROOT="$(cd "${EXT_ROOT}/../.." && pwd)"
SDK_DIR="${EXT_ROOT}/azext_aks_preview/vendored_sdks/azure_mgmt_preview_aks"
RECORDINGS_DIR="${EXT_ROOT}/azext_aks_preview/tests/latest/recordings"

# ──────────────────────────── Portable sed -i ────────────────────────────
# GNU sed uses `sed -i`, BSD/macOS sed requires `sed -i ''`. Detect once.
if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(sed -i)
else
    SED_INPLACE=(sed -i '')
fi

# ──────────────────────────── Auto-detect extension version ──────────────
SETUP_PY="${EXT_ROOT}/setup.py"
if [[ -z "${OLD_VER}" ]]; then
    OLD_VER=$(grep '^VERSION = ' "${SETUP_PY}" | sed 's/VERSION = "\(.*\)"/\1/')
    echo "Auto-detected current version: ${OLD_VER}"
fi
if [[ -z "${NEW_VER}" ]]; then
    # Increment the last numeric segment: 20.0.0b1 → 20.0.0b2, 1.2.3 → 1.2.4
    NEW_VER=$(python3 -c "
import re, sys
v = sys.argv[1]
m = re.match(r'^(.*?)(\\d+)$', v)
if m:
    print(m.group(1) + str(int(m.group(2)) + 1))
else:
    sys.exit(f'Cannot auto-increment version: {v}')
" "${OLD_VER}")
    echo "Auto-computed new version:     ${NEW_VER}"
fi

echo "============================================="
echo " aks-preview SDK bump: ${OLD_API} → ${NEW_API}"
echo " Extension version:   ${OLD_VER} → ${NEW_VER}"
echo "============================================="
echo ""

# ──────────────────────────── Helpers ────────────────────────────────────
check_repo_clean() {
    local repo_path="$1"
    local repo_name="$2"
    if [[ -n "$(git -C "${repo_path}" status --porcelain)" ]]; then
        echo "ERROR: ${repo_name} repo has uncommitted local changes."
        echo "       Path: ${repo_path}"
        echo "       Please commit or stash your changes first."
        exit 1
    fi
}

restore_repo() {
    local repo_path="$1"
    local saved_ref="$2"
    local repo_name="$3"
    echo "    Restoring ${repo_name} to ${saved_ref} ..."
    git -C "${repo_path}" checkout -- . 2>/dev/null || true
    git -C "${repo_path}" clean -fd 2>/dev/null || true
    git -C "${repo_path}" checkout "${saved_ref}" 2>/dev/null || true
}

# ──────────────────────────── Pre-flight: validate repos ─────────────────
echo ">>> Pre-flight: Validating repository states ..."

# CLI repo: must have no local changes
check_repo_clean "${CLI_REPO}" "azure-cli"

# Spec repo: must be clean
check_repo_clean "${SPEC_REPO}" "azure-rest-api-specs"

# SDK repo: must be clean
check_repo_clean "${SDK_REPO}" "azure-sdk-for-python"

echo "    All repos are clean."
echo ""

# ──────────────────────────── Prepare repos ──────────────────────────────
echo ">>> Preparing external repos ..."

# Save original branch (or SHA if detached) for repos we need to restore
SPEC_SAVED_REF="$(git -C "${SPEC_REPO}" symbolic-ref --short HEAD 2>/dev/null || git -C "${SPEC_REPO}" rev-parse HEAD)"
SDK_SAVED_REF="$(git -C "${SDK_REPO}" symbolic-ref --short HEAD 2>/dev/null || git -C "${SDK_REPO}" rev-parse HEAD)"

# Trap: restore spec and sdk repos on exit (success or failure)
cleanup() {
    echo ""
    echo ">>> Restoring external repos ..."
    restore_repo "${SPEC_REPO}" "${SPEC_SAVED_REF}" "azure-rest-api-specs"
    restore_repo "${SDK_REPO}"  "${SDK_SAVED_REF}"  "azure-sdk-for-python"
    echo "    Done."
}
trap cleanup EXIT

# Spec repo: pull latest main
echo "    azure-rest-api-specs: checking out main and pulling latest ..."
git -C "${SPEC_REPO}" checkout main
git -C "${SPEC_REPO}" pull origin main

# SDK repo: pull latest main
echo "    azure-sdk-for-python: checking out main and pulling latest ..."
git -C "${SDK_REPO}" checkout main
git -C "${SDK_REPO}" pull origin main

# CLI repo: checkout dev and pull latest (not restored on exit)
echo "    azure-cli: checking out dev and pulling latest ..."
git -C "${CLI_REPO}" checkout dev
git -C "${CLI_REPO}" pull origin dev

echo ""

# ──────────────────────────── Step 0: Git branch setup ───────────────────
echo ">>> Step 0: Pulling latest main and creating a new branch ..."
pushd "${REPO_ROOT}" > /dev/null
git checkout main
git pull origin main
BRANCH_NAME="bump-aks-preview-sdk-${NEW_API}"
echo "    Creating branch: ${BRANCH_NAME}"
# Delete the branch if it already exists (e.g. from a previous failed run)
git branch -D "${BRANCH_NAME}" 2>/dev/null || true
git checkout -b "${BRANCH_NAME}"
popd > /dev/null
echo ""

# ──────────────────────────── Step 1: Generate new SDK ───────────────────
if [[ "${SKIP_SDK_GEN}" == false ]]; then
    echo ">>> Step 1: Generating new SDK via tsp compile ..."

    # Derived paths for SDK generation
    TSP_PROJECT="${SPEC_REPO}/specification/containerservice/resource-manager/Microsoft.ContainerService/aks"
    SDK_PACKAGE="${SDK_REPO}/sdk/containerservice/azure-mgmt-containerservice"
    SDK_MODULE="${SDK_PACKAGE}/azure/mgmt/containerservice"

    # Determine emitter version from SDK repo's eng/emitter-package.json
    EMITTER_VERSION=$(python3 -c "import json; print(json.load(open('${SDK_REPO}/eng/emitter-package.json'))['dependencies']['@azure-tools/typespec-python'])")
    echo "    Emitter version: @azure-tools/typespec-python@${EMITTER_VERSION}"

    # Check prerequisites
    echo "    Checking prerequisites ..."
    command -v node >/dev/null 2>&1 || { echo "ERROR: node is required"; exit 1; }
    command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm is required"; exit 1; }
    echo "      node : $(node --version)"
    echo "      npm  : $(npm --version)"
    [[ -f "${TSP_PROJECT}/tspconfig.yaml" ]] || { echo "ERROR: tspconfig.yaml not found at ${TSP_PROJECT}"; exit 1; }

    # Install TypeSpec dependencies in the spec repo
    echo "    Installing TypeSpec dependencies in spec repo ..."
    pushd "${SPEC_REPO}" > /dev/null
    npm ci
    popd > /dev/null

    # Install the Python emitter into the spec repo so tsp compile can find it
    echo "    Installing Python emitter (@azure-tools/typespec-python@${EMITTER_VERSION}) ..."
    pushd "${SPEC_REPO}" > /dev/null
    npm install "@azure-tools/typespec-python@${EMITTER_VERSION}" --no-save
    popd > /dev/null

    # Generate the Python SDK via tsp compile
    echo "    Compiling TypeSpec → Python SDK ..."
    pushd "${TSP_PROJECT}" > /dev/null
    npx tsp compile . \
        --emit @azure-tools/typespec-python \
        --output-dir "${SDK_REPO}"
    popd > /dev/null

    # Vendor the generated SDK into aks-preview extension
    echo "    Vendoring generated SDK into aks-preview ..."
    if [[ ! -d "${SDK_MODULE}" ]]; then
        echo "ERROR: Expected generated module not found at ${SDK_MODULE}"
        exit 1
    fi

    mkdir -p "${SDK_DIR}"
    echo "      Cleaning ${SDK_DIR} ..."
    find "${SDK_DIR}" -mindepth 1 -not -path '*/__pycache__/*' -not -name '__pycache__' -delete 2>/dev/null || true

    echo "      Copying ${SDK_MODULE}/ → ${SDK_DIR}/ ..."
    cp -R "${SDK_MODULE}/"* "${SDK_DIR}/"

    echo "    SDK generation + vendoring complete."
    echo ""
else
    echo ">>> Step 1: Skipped (--skip-sdk-gen)"
    echo ""
fi

# ──────────────────────────── Step 2: Update _version.py ─────────────────
echo ">>> Step 2: Updating SDK _version.py ..."
VERSION_FILE="${SDK_DIR}/_version.py"
if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "ERROR: ${VERSION_FILE} not found"; exit 1
fi
# Write the new API version into _version.py so the vendored SDK reflects it
"${SED_INPLACE[@]}" "s/^VERSION = .*/VERSION = \"${NEW_API}\"/" "${VERSION_FILE}"
echo "    ${VERSION_FILE} → VERSION = \"${NEW_API}\""
echo ""

# ──────────────────────────── Step 3: Replace API version in recordings ──
echo ">>> Step 3: Replacing API version in test recordings ..."
echo "    ${OLD_API} → ${NEW_API}"
echo "    Directory: ${RECORDINGS_DIR}"
RECORDING_COUNT=$(find "${RECORDINGS_DIR}" -name '*.yaml' | wc -l | tr -d ' ')
echo "    Files to process: ${RECORDING_COUNT}"

find "${RECORDINGS_DIR}" -name '*.yaml' -print0 | \
    xargs -0 -P "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" \
    "${SED_INPLACE[@]}" "s|${OLD_API}|${NEW_API}|g"

echo "    Done."
echo ""

# ──────────────────────────── Step 4: Update metadata files ──────────────
echo ">>> Step 4: Updating setup.py, HISTORY.rst, README.rst ..."

# 4a. setup.py
SETUP_PY="${EXT_ROOT}/setup.py"
echo "    setup.py: VERSION ${OLD_VER} → ${NEW_VER}"
"${SED_INPLACE[@]}" "s/^VERSION = \"${OLD_VER}\"/VERSION = \"${NEW_VER}\"/" "${SETUP_PY}"

# 4b. HISTORY.rst
HISTORY_RST="${EXT_ROOT}/HISTORY.rst"
echo "    HISTORY.rst: adding ${NEW_VER} section"
python3 - "${HISTORY_RST}" "${NEW_VER}" "${NEW_API}" "${OLD_VER}" <<'PYEOF'
import sys

history_path, new_ver, new_api, old_ver = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
bump_line = f"* Bump API version to {new_api}.\n"

with open(history_path, "r") as f:
    lines = f.readlines()

# Check if new_ver section already exists
new_ver_marker = new_ver + "\n"
existing_idx = None
for idx, line in enumerate(lines):
    if line == new_ver_marker:
        existing_idx = idx
        break

if existing_idx is not None:
    # Section exists — find its first bullet line and prepend the bump entry
    # Skip the underline (++++++)
    insert_at = existing_idx + 2
    lines.insert(insert_at, bump_line)
    print(f"    Appended bump entry to existing {new_ver} section in HISTORY.rst")
else:
    # Section doesn't exist — insert a new one before the old_ver section
    old_ver_marker = old_ver + "\n"
    old_idx = None
    for idx, line in enumerate(lines):
        if line == old_ver_marker:
            old_idx = idx
            break
    if old_idx is not None:
        block = [f"\n{new_ver}\n", f"++++++\n", bump_line]
        for j, bl in enumerate(block):
            lines.insert(old_idx + j, bl)
        print(f"    Inserted {new_ver} section into HISTORY.rst")
    else:
        print(f"  WARNING: Could not find '{old_ver}' section in HISTORY.rst.")
        print(f"           Please manually insert the {new_ver} section.")

with open(history_path, "w") as f:
    f.writelines(lines)
PYEOF

# 4c. README.rst
README_RST="${EXT_ROOT}/README.rst"
echo "    README.rst: updating version ↔ API mapping"
python3 - "${README_RST}" "${NEW_VER}" "${NEW_API}" "${OLD_VER}" <<'PYEOF'
import sys

readme_path, new_ver, new_api, old_ver = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(readme_path, "r") as f:
    lines = f.readlines()

# Find the LAST "~ latest" row (the API version table, not the dependency table)
last_latest_idx = None
for idx, line in enumerate(lines):
    if "~ latest" in line:
        last_latest_idx = idx

if last_latest_idx is None:
    print("  WARNING: Could not find '~ latest' row in README.rst.")
    print("           Please manually update the API version table.")
else:
    i = last_latest_idx
    # Replace "~ latest" with "~ <old_ver>" on this line
    lines[i] = lines[i].replace("~ latest", f"~ {old_ver}")
    # Ensure the comment column line (i+2) ends with newline
    # (may be missing if it's the last line of the file)
    if i + 2 < len(lines) and not lines[i + 2].endswith("\n"):
        lines[i + 2] += "\n"
    # Insert new row after the current row + its 2 column lines
    insert_at = i + 3
    new_rows = [
        f"    * - {new_ver} ~ latest\n",
        f"      - {new_api}\n",
        f"      -\n",
    ]
    for j, row in enumerate(new_rows):
        lines.insert(insert_at + j, row)
    print(f"    Updated README.rst with {new_ver} → {new_api}")

with open(readme_path, "w") as f:
    f.writelines(lines)
PYEOF

echo "    Done."
echo ""

# ──────────────────────────── Step 5: Setup & run tests ──────────────────
if [[ "${SKIP_TESTS}" == false ]]; then
    echo ">>> Step 5: Setting up azdev and running tests ..."

    # azdev setup (CLI repo already on latest dev from pre-flight)
    echo "    Running: azdev setup ..."
    azdev setup -c "${CLI_REPO}" -r "${REPO_ROOT}"

    # Register the extension
    echo "    Running: azdev extension add aks-preview ..."
    azdev extension add aks-preview

    # Force-refresh command index
    echo "    Refreshing command index ..."
    az aks fake 2>/dev/null || true

    # Run tests
    echo ""
    echo "    Running: azdev test azext_aks_preview ..."
    azdev test azext_aks_preview

    echo ""
    echo ">>> Tests completed."
else
    echo ">>> Step 5: Skipped (--skip-tests)"
fi

echo ""
echo "============================================="
echo " SDK bump complete!"
echo " Please review the changes and commit."
echo "============================================="
