#!/usr/bin/env bash
# ccdc-cli — CCDC competition hardening toolkit
# Linux entry point
set -euo pipefail

# ── Require Root ──
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m ccdc-cli requires root. Run with: sudo ./ccdc.sh $*"
    exit 1
fi

# ── Constants ──
CCDC_VERSION="0.1.0"
CCDC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCDC_CONF="${CCDC_DIR}/.ccdc.conf"

# ── Global State (set by detect or config) ──
CCDC_OS=""
CCDC_OS_FAMILY=""
CCDC_OS_VERSION=""
CCDC_PKG=""
CCDC_FW_BACKEND=""
CCDC_FW_AVAILABLE=()
CCDC_BACKUP_DIR=""
CCDC_UNDO_DIR=""
CCDC_LOG=""
CCDC_WAZUH_IP=""
CCDC_SPLUNK_IP=""
CCDC_SCORED_TCP=""
CCDC_SCORED_UDP=""

# ── Global Flags ──
CCDC_NO_PROMPT=false
CCDC_DRY_RUN=false
CCDC_VERBOSE=false
CCDC_HELP=false
CCDC_UNDO=false

# ── Source Phase 0 Libraries (order matters) ──
source "${CCDC_DIR}/lib/linux/common.sh"
source "${CCDC_DIR}/lib/linux/detect.sh"
source "${CCDC_DIR}/lib/linux/config.sh"
source "${CCDC_DIR}/lib/linux/undo.sh"

# ── Load Config (or detect defaults) ──
ccdc_config_load

# If no config file and no detection done yet, run detection
if [[ -z "$CCDC_OS" ]]; then
    ccdc_detect_all
fi

# ── Parse Global Flags ──
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)     CCDC_HELP=true; shift ;;
        --undo)        CCDC_UNDO=true; shift ;;
        --no-prompt)   CCDC_NO_PROMPT=true; shift ;;
        --dry-run)     CCDC_DRY_RUN=true; shift ;;
        --verbose|-v)  CCDC_VERBOSE=true; shift ;;
        --version)     echo "ccdc-cli ${CCDC_VERSION}"; exit 0 ;;
        --)            shift; args+=("$@"); break ;;
        *)             args+=("$1"); shift ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

# ── Extract Category and Command ──
CCDC_CATEGORY="${1:-}"
CCDC_COMMAND="${2:-}"
shift 2 2>/dev/null || true

# If no category and help requested, show usage
if [[ -z "$CCDC_CATEGORY" ]]; then
    if [[ "$CCDC_HELP" == true ]]; then
        ccdc_usage
        exit 0
    fi
    ccdc_usage
    exit 1
fi

# ── Alias Resolution ──
ccdc_resolve_category() {
    case "$1" in
        passwd|pw)       echo "passwd" ;;
        backup|bak)      echo "backup" ;;
        discover|disc)   echo "discover" ;;
        service|svc)     echo "service" ;;
        firewall|fw)     echo "firewall" ;;
        harden|hrd)      echo "harden" ;;
        siem)            echo "siem" ;;
        install|inst)    echo "install" ;;
        net)             echo "net" ;;
        copy-paster|cp)  echo "copy-paster" ;;
        config|cfg)      echo "config" ;;
        undo)            echo "undo" ;;
        comp-start)      echo "comp-start" ;;
        *)               echo "" ;;
    esac
}

category="$(ccdc_resolve_category "$CCDC_CATEGORY")"

if [[ -z "$category" ]]; then
    ccdc_log error "Unknown category: ${CCDC_CATEGORY}"
    ccdc_usage
    exit 1
fi

# ── Initialize Logging (after config sets CCDC_LOG) ──
ccdc_log_init

# ── Route to Module ──
case "$category" in
    config)
        ccdc_config_handler "$CCDC_COMMAND" "$@"
        ;;
    undo)
        ccdc_undo_handler "$CCDC_COMMAND" "$@"
        ;;
    comp-start)
        module_file="${CCDC_DIR}/lib/linux/comp-start.sh"
        if [[ ! -f "$module_file" ]]; then
            ccdc_log warn "comp-start module not yet built. Run individual commands instead."
            exit 1
        fi
        source "$module_file"
        ccdc_comp_start_handler "$@"
        ;;
    passwd|backup|discover|service|firewall|harden|siem|install|net)
        module_file="${CCDC_DIR}/lib/linux/${category}.sh"
        if [[ ! -f "$module_file" ]]; then
            ccdc_log warn "Module '${category}' not yet built. Coming soon."
            exit 1
        fi
        source "$module_file"
        "ccdc_${category}_handler" "$CCDC_COMMAND" "$@"
        ;;
    copy-paster)
        script="${CCDC_DIR}/lib/copy-paster/copy-paster.sh"
        if [[ ! -f "$script" ]]; then
            ccdc_log warn "copy-paster not yet built. Coming soon."
            exit 1
        fi
        bash "$script" "$@"
        ;;
    *)
        ccdc_log error "Unknown category: ${category}"
        ccdc_usage
        exit 1
        ;;
esac
