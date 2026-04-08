#!/usr/bin/env bash
#
# docker-entrypoint.sh
#
# Copies any custom plugins from the mounted volume into the APISIX plugin
# directory, then exec's the provided command (default: `apisix start`).
#
set -euo pipefail

CUSTOM_PLUGINS_DIR="/opt/custom-plugins/apisix/plugins"
APISIX_PLUGINS_DIR="/usr/local/apisix/apisix/plugins"

if ls "${CUSTOM_PLUGINS_DIR}"/*.lua 2>/dev/null 1>&2; then
    echo "[entrypoint] Copying custom plugins → ${APISIX_PLUGINS_DIR}"
    cp -r "${CUSTOM_PLUGINS_DIR}"/*.lua "${APISIX_PLUGINS_DIR}/"
else
    echo "[entrypoint] No custom plugins found in ${CUSTOM_PLUGINS_DIR}, skipping copy."
fi

exec "$@"
