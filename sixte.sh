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

ensure_test_scaffold() {
    if [[ ! -d "${PROJECT_DIR}/apisix/plugins" ]]; then
        warn "Creating ${PROJECT_DIR}/apisix/plugins/ directory..."
        mkdir -p "${PROJECT_DIR}/apisix/plugins"
    fi
    if [[ ! -d "${PROJECT_DIR}/t" ]]; then
        warn "Creating ${PROJECT_DIR}/t/ directory..."
        mkdir -p "${PROJECT_DIR}/t"
    fi
}

ensure_test_image() {
    if ! docker image inspect "${SIXTE_IMAGE_NAME}" &>/dev/null; then
        warn "Image '${SIXTE_IMAGE_NAME}' not found. Building it now..."
        cmd_build
    fi
}

_ensure_single_config() {
    local target_file="$1"
    local template_file="$2"

    if [[ ! -f "${target_file}" ]]; then
        warn "Config not found: ${target_file}"
        if [[ -f "${template_file}" ]]; then
            read -p "Do you want to generate this default configuration file? [y/N] " -r REPLY
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                warn "Copying default config from template..."
                mkdir -p "$(dirname "${target_file}")"
                cp "${template_file}" "${target_file}"
                info "Created ${target_file} ✓"
            else
                err "Run 'sixte init --config' first, or create ${target_file} manually."
                exit 1
            fi
        else
            err "Template config not found at ${template_file}."
            err "Run 'sixte init --config' first, or create ${target_file} manually."
            exit 1
        fi
    fi
}

ensure_config() {
    APISIX_CONF_PATH="${APISIX_CONF_PATH:-/conf}"
    local apisix_file="${PROJECT_DIR}${APISIX_CONF_PATH}/apisix.yaml"
    local config_file="${PROJECT_DIR}${APISIX_CONF_PATH}/config.yaml"
    local template_apisix="${SIXTE_HOME}/assets/conf/apisix"
    local template_config="${SIXTE_HOME}/assets/conf/config_standalone"

    _ensure_single_config "${apisix_file}" "${template_apisix}"
    _ensure_single_config "${config_file}" "${template_config}"
}

# ─── Commands ────────────────────────────────────────────────────────
cmd_build() {
    local build_opts=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) build_opts="--no-cache"; shift ;;
            *) err "Unknown option for build: $1"; exit 1 ;;
        esac
    done

    info "Building APISIX test image (${SIXTE_IMAGE_NAME})..."
    docker build ${build_opts} -t "${SIXTE_IMAGE_NAME}" -f "${SIXTE_HOME}/Dockerfile" "${SIXTE_HOME}"
    info "Build complete ✓"
}

cmd_run() {
    ensure_config
    info "Starting APISIX..."
    warn "Support only standalone mode!"
    info "Config dir    : ${PROJECT_DIR}${APISIX_CONF_PATH}/config.yaml"
    info "Routes config : ${PROJECT_DIR}${APISIX_CONF_PATH}/apisix.yaml"
    info "Plugins dir   : ${PROJECT_DIR}/apisix/plugins/"
    info "Listening on  : http://localhost:9080"
    docker compose -f "${SIXTE_HOME}/docker-compose.yml" up -d apisix
}

cmd_down() {
    info "Stopping APISIX environment..."
    docker compose -f "${SIXTE_HOME}/docker-compose.yml" down apisix
}

cmd_restart() {
    info "Restarting APISIX environment to reload plugins..."
    docker compose -f "${SIXTE_HOME}/docker-compose.yml" restart apisix
}

cmd_logs() {
    info "Tailing APISIX logs..."
    docker compose -f "${SIXTE_HOME}/docker-compose.yml" logs -f apisix
}

cmd_test() {
    local target_paths=""
    local test_paths=""
    if [[ $# -eq 0 ]]; then
        target_paths="/opt/custom-plugins/t/"
        test_paths="t/"
    else
        for path in "$@"; do
            path="${path#./}"
            if [[ "$path" == t/* || "$path" == "t" ]]; then
                target_paths="${target_paths} /opt/custom-plugins/${path}"
            else
                target_paths="${target_paths} ${path}"
            fi
            test_paths="${test_paths} ${path}"
        done
    fi

    ensure_test_image
    ensure_test_scaffold
    info "Starting test environment (single container)..."
    info "version: ${APISIX_VERSION}"
    info "Running tests (prove -r ${test_paths}) inside the container..."

    docker compose -f "${SIXTE_HOME}/docker-compose.yml" run --name ${SIXTE_NAME} --rm apisix-testing-environment bash -c \
    "etcd --listen-client-urls http://0.0.0.0:2379 \
           --advertise-client-urls http://0.0.0.0:2379 \
           --data-dir /tmp/etcd-data \
           &>/tmp/etcd.log & \
     sleep 2 && \
     cp -r /opt/custom-plugins/apisix/plugins/*.lua /usr/local/apisix-src/apisix/plugins/ 2>/dev/null || true && \
     prove -I/usr/local/test-nginx/lib -I/usr/local/apisix-src -r ${target_paths}"
}

cmd_init() {
    local init_config=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config) init_config=true; shift ;;
            *) err "Unknown option for init: $1"; exit 1 ;;
        esac
    done

    info "Initialising plugin project in ${PROJECT_DIR}..."
    if [[ ! -d "${PROJECT_DIR}/apisix/plugins" ]]; then
        mkdir -p "${PROJECT_DIR}/apisix/plugins"
        info "  ${PROJECT_DIR}/apisix/plugins/      — place your Lua plugins here"
    fi
    if [[ ! -d "${PROJECT_DIR}/t" ]]; then
        mkdir -p "${PROJECT_DIR}/t"
        info "  ${PROJECT_DIR}/t/                   — place your .t test files here"
    fi
    if [[ ! -f "${PROJECT_DIR}/.editorconfig" ]]; then
        cp "${SIXTE_HOME}/assets/init/editorconfig" "${PROJECT_DIR}/.editorconfig"
        info "  ${PROJECT_DIR}/.editorconfig        — Editor configuration"
    fi

    if [[ "$init_config" == true ]]; then
        ensure_config
    fi

    info "Project scaffolding created ✓"
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
        build)      preflight; cmd_build "$@" ;;
        run)        preflight; cmd_run "$@" ;;
        test)       preflight; cmd_test "$@" ;;
        down)       preflight; cmd_down "$@" ;;
        restart)    preflight; cmd_restart "$@" ;;
        logs|log)   preflight; cmd_logs "$@" ;;
        init)       cmd_init "$@" ;;
        help|--help|-h)
            usage ;;
        *)
            err "Unknown command: ${cmd}"
            usage
            exit 1 ;;
    esac
}

main "$@"
