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
APISIX_TEST_VERSION=3.15.0
export APISIX_TEST_VERSION
SIXTE_NAME="apisix-testing-environment"
export SIXTE_NAME
IMAGE_NAME="${SIXTE_NAME}:${APISIX_TEST_VERSION}"
export IMAGE_NAME

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
    if [[ ! -d "${PROJECT_DIR}/spec" ]]; then
        warn "Creating ${PROJECT_DIR}/spec/ directory..."
        mkdir -p "${PROJECT_DIR}/spec"
    fi
}

# ─── Ensure image is built ───────────────────────────────────────────
ensure_image() {
    if ! docker image inspect "${IMAGE_NAME}" &>/dev/null; then
        warn "Image '${IMAGE_NAME}' not found. Building it now..."
        cmd_build
    fi
}

ensure_etcd() {
    if ! docker container inspect "apisix-etcd" &>/dev/null; then
        info "Starting etcd..."
        docker compose -f "${SIXTE_HOME}/docker-compose.yml" up -d etcd > /dev/null 2>&1
        info "Etcd started ✓"
    fi
}

# ─── Commands ────────────────────────────────────────────────────────
cmd_build() {
    info "Building APISIX test image (${IMAGE_NAME})..."
    docker build -t "${IMAGE_NAME}" -f "${SIXTE_HOME}/Dockerfile" "${SIXTE_HOME}"
    info "Build complete ✓"
}

cmd_test() {
    ensure_image
    ensure_scaffold
    ensure_etcd
    info "Starting test environment..."
    info "version: ${APISIX_TEST_VERSION}"
    info "Running tests (prove -r t/) inside the container..."
    
    docker compose -f "${SIXTE_HOME}/docker-compose.yml" run --rm apisix-testing-environment bash -c \
    "cp -r /opt/custom-plugins/apisix/plugins/*.lua /usr/local/apisix-src/apisix/plugins/ && \
    prove -I/usr/local/test-nginx/lib -I/usr/local/apisix-src -r /apisix/t/"

    docker compose -f "${SIXTE_HOME}/docker-compose.yml" down etcd > /dev/null 2>&1
}

cmd_utest() {
    ensure_image
    ensure_scaffold
    info "Running Busted unit tests (spec/) inside the container..."

    docker compose -f "${SIXTE_HOME}/docker-compose.yml" run --rm apisix-testing-environment bash -c \
    "cd /opt/custom-plugins/ && \
    busted --lua=resty spec/"
}

cmd_init() {
    info "Initialising plugin project in ${PROJECT_DIR}..."
    if [[ ! -d "${PROJECT_DIR}/apisix/plugins" ]]; then
        mkdir "${PROJECT_DIR}/apisix/plugins"
    fi
    if [[ ! -d "${PROJECT_DIR}/t" ]]; then
        mkdir "${PROJECT_DIR}/t"
    fi
    if [[ ! -d "${PROJECT_DIR}/spec" ]]; then
        mkdir "${PROJECT_DIR}/spec"
    fi
    if [[ ! -f "${PROJECT_DIR}/.editorconfig" ]]; then
        cp "${SIXTE_HOME}/assets/init/editorconfig" "${PROJECT_DIR}/.editorconfig"
    fi
    if [[ ! -f "${PROJECT_DIR}/.luacheckrc" ]]; then
        cp "${SIXTE_HOME}/assets/init/luacheckrc" "${PROJECT_DIR}/.luacheckrc"
    fi
    if [[ ! -f "${PROJECT_DIR}/.busted" ]]; then
        cp "${SIXTE_HOME}/assets/init/busted" "${PROJECT_DIR}/.busted"
    fi

    info "Project scaffolding created ✓"
    info "  ${PROJECT_DIR}/apisix/plugins/  — place your Lua plugins here"
    info "  ${PROJECT_DIR}/t/               — place your .t test files here"
    info "  ${PROJECT_DIR}/spec/            — place your Busted *_spec.lua files here"
    info "  ${PROJECT_DIR}/.busted          — Busted configuration"
    info "  ${PROJECT_DIR}/.editorconfig    — Editor configuration"
    info "  ${PROJECT_DIR}/.luacheckrc      — Luacheck configuration"
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
        test)    preflight; cmd_test "$@" ;;
        utest)   preflight; cmd_utest "$@" ;;
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
