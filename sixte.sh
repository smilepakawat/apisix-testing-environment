#!/usr/bin/env bash
#
#  sixte — APISIX Plugin Testing Environment CLI
#
#  Usage:  sixte <command> [options]
#
#  Run this from your plugin project directory. The script discovers
#  the framework's Docker assets via SIXTE_HOME (defaults to the
#  directory containing this script).
#
set -euo pipefail

# ─── Colours & formatting ────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

info()    { echo -e "${GREEN}[sixte]${NC} $*"; }
warn()    { echo -e "${YELLOW}[sixte]${NC} $*"; }
err()     { echo -e "${RED}[sixte]${NC} $*" >&2; }

# ─── Resolve paths ───────────────────────────────────────────────────
# SIXTE_HOME: where Dockerfile, docker-compose.yml live
SIXTE_HOME="${SIXTE_HOME:-$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")" && pwd)}"
export SIXTE_HOME

# PROJECT_DIR: the current working directory
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
export PROJECT_DIR

# Container / image names
APISIX_VERSION=3.15.0
export APISIX_VERSION
APISIX_NAME="apisix"
export APISIX_NAME
APISIX_IMAGE_NAME="apache/apisix:${APISIX_VERSION}-debian"
export APISIX_IMAGE_NAME
SIXTE_NAME="apisix-testing-environment"
export SIXTE_NAME
SIXTE_IMAGE_NAME="${SIXTE_NAME}:${APISIX_VERSION}"
export SIXTE_IMAGE_NAME

# ─── Pre-flight checks ──────────────────────────────────────────────
preflight() {
    if ! command -v docker &>/dev/null; then
        err "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! docker info &>/dev/null 2>&1; then
        err "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    if ! docker compose version &>/dev/null; then
        err "Docker Compose is not installed. Please install Docker Compose."
        exit 1
    fi
}

# ─── Ensure project scaffolding exists ───────────────────────────────
ensure_scaffold() {
    if [[ ! -d "${PROJECT_DIR}/apisix/plugins" ]]; then
        warn "Creating ${PROJECT_DIR}/apisix/plugins/ directory..."
        mkdir -p "${PROJECT_DIR}/apisix/plugins"
    fi
    if [[ ! -d "${PROJECT_DIR}/t" ]]; then
        warn "Creating ${PROJECT_DIR}/t/ directory..."
        mkdir -p "${PROJECT_DIR}/t"
    fi
}

# ─── Ensure image is built ───────────────────────────────────────────
ensure_image() {
    if ! docker image inspect "${_NAME}" &>/dev/null; then
        warn "Image '${SIXTE_IMAGE_NAME}' not found. Building it now..."
        cmd_build
    fi
}

# ─── Commands ────────────────────────────────────────────────────────
cmd_build() {
    info "Building APISIX test image (${SIXTE_IMAGE_NAME})..."
    docker build -t "${SIXTE_IMAGE_NAME}" -f "${SIXTE_HOME}/Dockerfile" "${SIXTE_HOME}"
    info "Build complete ✓"
}

# cmd_run() {
#     ensure_image
#     ensure_scaffold
#     info "Starting APISIX..."
#     info "  Routes config : ${PROJECT_DIR}/apisix/conf/apisix.yaml"
#     info "  Plugins dir   : ${PROJECT_DIR}/apisix/plugins/"
#     info "  Listening on  : http://localhost:9080"
#     docker compose -f "${SIXTE_HOME}/docker-compose.yml" up apisix
# }

cmd_test() {
    ensure_image
    ensure_scaffold
    info "Starting test environment (single container)..."
    info "version: ${APISIX_VERSION}"
    info "Running tests (prove -r t/) inside the container..."

    docker compose -f "${SIXTE_HOME}/docker-compose.yml" run --rm apisix-testing-environment bash -c \
    "etcd --listen-client-urls http://0.0.0.0:2379 \
           --advertise-client-urls http://0.0.0.0:2379 \
           --data-dir /tmp/etcd-data \
           &>/tmp/etcd.log & \
     sleep 2 && \
     cp -r /opt/custom-plugins/apisix/plugins/*.lua /usr/local/apisix-src/apisix/plugins/ 2>/dev/null || true && \
     prove -I/usr/local/test-nginx/lib -I/usr/local/apisix-src -r /opt/custom-plugins/t/"
}

cmd_init() {
    info "Initialising plugin project in ${PROJECT_DIR}..."
    if [[ ! -d "${PROJECT_DIR}/apisix/plugins" ]]; then
        mkdir -p "${PROJECT_DIR}/apisix/plugins"
    fi
    if [[ ! -d "${PROJECT_DIR}/t" ]]; then
        mkdir -p "${PROJECT_DIR}/t"
    fi
    if [[ ! -f "${PROJECT_DIR}/.editorconfig" ]]; then
        cp "${SIXTE_HOME}/assets/init/editorconfig" "${PROJECT_DIR}/.editorconfig"
    fi
    # Scaffold an apisix.yaml for standalone mode (if one doesn't exist yet)
    if [[ ! -f "${PROJECT_DIR}/apisix/conf/apisix.yaml" ]]; then
        cp "${SIXTE_HOME}/assets/conf/apisix.yaml" "${PROJECT_DIR}/apisix/conf/apisix.yaml"
    fi

    info "Project scaffolding created ✓"
    info "  ${PROJECT_DIR}/apisix/plugins/      — place your Lua plugins here"
    info "  ${PROJECT_DIR}/apisix/conf/apisix.yaml — standalone routes/upstreams config"
    info "  ${PROJECT_DIR}/t/                   — place your .t test files here"
    info "  ${PROJECT_DIR}/.editorconfig        — Editor configuration"
}

# ─── Usage / Help ────────────────────────────────────────────────────
usage() {
    echo -e "$(<"${SIXTE_HOME}/assets/help")"
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "${cmd}" in
        build)   preflight; cmd_build "$@" ;;
        # run)     preflight; cmd_run "$@" ;;
        test)    preflight; cmd_test "$@" ;;
        init)    cmd_init "$@" ;;
        help|--help|-h)
            usage ;;
        *)
            err "Unknown command: ${cmd}"
            usage
            exit 1 ;;
    esac
}

main "$@"
