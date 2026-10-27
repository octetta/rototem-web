#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION_FILE="${ROOT_DIR}/SKRED_VERSION"
if [ ! -f "${VERSION_FILE}" ]; then
  echo "Error: SKRED_VERSION file not found at ${VERSION_FILE}" >&2
  exit 1
fi

VERSION="${1:-$(tr -d '[:space:]' < "${VERSION_FILE}")}"
echo "Fetching Skred WASM assets for version: ${VERSION}..."

TARGET_DIR="${ROOT_DIR}/vendor/skred"
mkdir -p "${TARGET_DIR}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

ARCHIVE_NAME="skred-${VERSION}-maxed-wasm.zip"
DOWNLOAD_URL="https://github.com/octetta/pulp/releases/download/v${VERSION}/${ARCHIVE_NAME}"

echo "Downloading ${DOWNLOAD_URL}..."
curl -fsSL "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ARCHIVE_NAME}"

echo "Extracting into ${TARGET_DIR}..."
unzip -q -o "${TMP_DIR}/${ARCHIVE_NAME}" -d "${TMP_DIR}/extracted"

# Find and place skred_api.js and skred_api.wasm directly in TARGET_DIR
find "${TMP_DIR}/extracted" -type f -name "skred_api.*" -exec cp -f {} "${TARGET_DIR}/" \;

# Sync to public/vendor for dev server / static serving
mkdir -p "${ROOT_DIR}/public/vendor"
cp -r "${ROOT_DIR}/vendor/"* "${ROOT_DIR}/public/vendor/"

echo "Done! Vendored Skred assets in ${TARGET_DIR} and synced to public/vendor/:"
ls -la "${TARGET_DIR}"
