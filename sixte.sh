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
}

# ─── Ensure image is built ───────────────────────────────────────────
ensure_image() {
    if ! docker image inspect "${IMAGE_NAME}" &>/dev/null; then
        warn "Image '${IMAGE_NAME}' not found. Building it now..."
        cmd_build
    fi
}

# ─── Commands ────────────────────────────────────────────────────────
cmd_build() {
    info "Building APISIX test image (${IMAGE_NAME})..."
    docker build -t "${IMAGE_NAME}" -f "${SIXTE_HOME}/Dockerfile.test" "${SIXTE_HOME}"
    info "Build complete ✓"
}

cmd_test() {
    ensure_image
    ensure_scaffold
    info "Starting test environment..."
    info "version: ${APISIX_TEST_VERSION}"
    info "Running tests (prove -r t/) inside the container..."
    
    docker compose -f "${SIXTE_HOME}/docker-compose.yml" run --rm apisix-testing-environment bash -c \
    "cp -r /opt/custom-plugins/apisix/plugins/*.lua /usr/local/apisix-src/apisix/plugins/ && \
    prove -I/usr/local/test-nginx/lib -I/usr/local/apisix-src -r /apisix/t/"

    docker compose -f "${SIXTE_HOME}/docker-compose.yml" down etcd > /dev/null 2>&1
}

cmd_init() {
    info "Initialising plugin project in ${PROJECT_DIR}..."
    mkdir -p "${PROJECT_DIR}/apisix/plugins"
    mkdir -p "${PROJECT_DIR}/t"

    if [[ ! -f "${PROJECT_DIR}/apisix/plugins/.gitkeep" ]]; then
        touch "${PROJECT_DIR}/apisix/plugins/.gitkeep"
    fi
    if [[ ! -f "${PROJECT_DIR}/t/.gitkeep" ]]; then
        touch "${PROJECT_DIR}/t/.gitkeep"
    fi
    if [[ ! -f "${PROJECT_DIR}/.editorconfig" ]]; then
        cp "${SIXTE_HOME}/assets/init/editorconfig" "${PROJECT_DIR}/.editorconfig"
    fi
    if [[ ! -f "${PROJECT_DIR}/.luacheckrc" ]]; then
        cp "${SIXTE_HOME}/assets/init/luacheckrc" "${PROJECT_DIR}/.luacheckrc"
    fi

    info "Project scaffolding created ✓"
    info "  ${PROJECT_DIR}/apisix/plugins/  — place your Lua plugins here"
    info "  ${PROJECT_DIR}/t/       — place your .t test files here"
}

# ─── Usage / Help ────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}sixte${NC} — APISIX Plugin Testing Environment CLI

${CYAN}USAGE${NC}
    sixte <command> [options]

${CYAN}COMMANDS${NC}
    ${GREEN}build${NC}       Build the APISIX test Docker image
    ${GREEN}test${NC}        Run prove -r t/ inside the container
    ${GREEN}init${NC}        Initialise a new plugin project (create plugins/ and t/)
    ${GREEN}help${NC}        Show this help message

${CYAN}ENVIRONMENT${NC}
    SIXTE_HOME      Path to the sixte framework directory
                    (default: directory containing this script)
    PROJECT_DIR     Path to the plugin project directory
                    (default: current working directory)

${CYAN}EXAMPLES${NC}
    # From your plugin project directory:
    sixte build              # Build the test image (first time)
    sixte test               # Run your tests

EOF
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "${cmd}" in
        build)   preflight; cmd_build "$@" ;;
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
