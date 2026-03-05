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

# PROJECT_DIR: the current working directory (where plugins/ and t/ live)
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
export PROJECT_DIR

# Container / image names
COMPOSE_PROJECT_NAME="sixte"
export COMPOSE_PROJECT_NAME
IMAGE_NAME="apisix-testing:latest"
CONTAINER_NAME="sixte-apisix"

# ─── Detect docker compose command ───────────────────────────────────
detect_compose() {
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        err "Neither 'docker compose' nor 'docker-compose' found. Please install Docker with Compose."
        exit 1
    fi
}

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

    detect_compose
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

# ─── Compose wrapper ────────────────────────────────────────────────
compose() {
    ${COMPOSE_CMD} -f "${SIXTE_HOME}/docker-compose.yml" -p "${COMPOSE_PROJECT_NAME}" "$@"
}

# ─── Commands ────────────────────────────────────────────────────────

cmd_build() {
    info "Building APISIX test image (${IMAGE_NAME})..."
    docker build -t "${IMAGE_NAME}" -f "${SIXTE_HOME}/Dockerfile" "${SIXTE_HOME}"
    info "Build complete ✓"
}

cmd_up() {
    ensure_image
    ensure_scaffold
    info "Starting APISIX (standalone mode)..."
    info "  SIXTE_HOME   = ${SIXTE_HOME}"
    info "  PROJECT_DIR  = ${PROJECT_DIR}"
    compose up -d "$@"
    info "APISIX is running ✓"
    info "  HTTP  → http://localhost:9080"
    info "  HTTPS → https://localhost:9443"
}

cmd_down() {
    info "Stopping APISIX..."
    compose down "$@"
    info "Stopped ✓"
}

cmd_restart() {
    cmd_down
    cmd_up
}

cmd_status() {
    compose ps
}

cmd_logs() {
    compose logs -f "$@"
}

cmd_test() {
    ensure_image
    ensure_scaffold
    info "Starting test environment..."
    compose up -d
    info "Running tests (prove -r t/) inside the container..."

    local rc=0
    docker exec -it "${CONTAINER_NAME}" bash -c \
        "cd /usr/local/apisix && TEST_NGINX_SERVROOT=/usr/local/apisix/servroot prove -v -I. -r t/" \
        || rc=$?

    info "Tearing down test environment..."
    compose down > /dev/null 2>&1

    if [[ ${rc} -eq 0 ]]; then
        info "All tests passed ✓"
    else
        err "Tests failed (exit code ${rc})"
    fi
    return ${rc}
}

cmd_shell() {
    info "Opening shell in APISIX container..."
    docker exec -it "${CONTAINER_NAME}" /bin/bash
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
    ${GREEN}up${NC}          Start the APISIX environment
    ${GREEN}down${NC}        Stop and remove containers
    ${GREEN}restart${NC}     Restart the environment (down + up)
    ${GREEN}status${NC}      Show container status
    ${GREEN}logs${NC}        Tail container logs
    ${GREEN}test${NC}        Run prove -r t/ inside the container
    ${GREEN}shell${NC}       Open a shell inside the APISIX container
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
    sixte up                 # Start APISIX
    sixte test               # Run your tests
    sixte logs               # Check logs if something fails
    sixte down               # Tear down when done

EOF
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "${cmd}" in
        build)   preflight; cmd_build "$@" ;;
        up)      preflight; cmd_up "$@" ;;
        down)    preflight; cmd_down "$@" ;;
        restart) preflight; cmd_restart "$@" ;;
        status)  preflight; cmd_status "$@" ;;
        logs)    preflight; cmd_logs "$@" ;;
        test)    preflight; cmd_test "$@" ;;
        shell)   preflight; cmd_shell "$@" ;;
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
