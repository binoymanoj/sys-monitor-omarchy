#!/bin/bash
set -euo pipefail

# System Monitor Plugin Installer for Omarchy

PLUGIN_ID="sys-monitor"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"

echo "=========================================="
echo " Installing Omarchy System Monitor Plugin "
echo "=========================================="

mkdir -p "${HOME}/.config/omarchy/plugins"
mkdir -p "${HOME}/.local/state/omarchy/settings"

if [[ -L "${TARGET_DIR}" || -d "${TARGET_DIR}" ]]; then
  echo "Removing existing link or folder at ${TARGET_DIR}..."
  rm -rf "${TARGET_DIR}"
fi

echo "Linking ${SOURCE_DIR} -> ${TARGET_DIR}..."
ln -s "${SOURCE_DIR}" "${TARGET_DIR}"

echo "Validating plugin..."
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "${TARGET_DIR}"
  echo "Rescanning Omarchy shell plugins..."
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins 2>/dev/null || true
  fi
  echo "Enabling plugin ${PLUGIN_ID}..."
  omarchy plugin enable "${PLUGIN_ID}" || true
else
  echo "omarchy CLI not found in PATH. Please reload omarchy shell manually."
fi

echo "=========================================="
echo " Installation Complete! "
echo " Topbar System Monitor is now active. "
echo " Click the bar widget to open settings. "
echo "=========================================="
