#!/usr/bin/env bash
# ccdc-cli: net module — firewall-aware downloads
# Depends on: common.sh, detect.sh, config.sh, undo.sh, firewall.sh

# Source firewall module for allow-internet/block-internet
_NET_FW_FILE="${CCDC_DIR}/lib/linux/firewall.sh"
if [[ -f "$_NET_FW_FILE" ]]; then
    # Only source if not already loaded (check for handler function)
    type ccdc_firewall_handler &>/dev/null || source "$_NET_FW_FILE"
fi

# ── Usage ──

ccdc_net_usage() {
    echo -e "${CCDC_BOLD}ccdc net${CCDC_NC} — Firewall-aware downloads"
    echo ""
    echo "Commands:"
    echo "  wget <url> [output]  Download file (opens outbound, downloads, closes)"
    echo "  curl <url>           Quick fetch to stdout"
    echo ""
    echo "Options:"
    echo "  --help"
    echo "  -h                   Show help"
    echo ""
    echo "These commands automatically open outbound 80,443,53 before downloading"
    echo "and close them after, even if the download fails."
    echo ""
    echo "Examples:"
    echo "  ccdc net wget https://example.com/tool.deb"
    echo "  ccdc net wget https://example.com/tool.deb /tmp/tool.deb"
    echo "  ccdc net curl https://api.example.com/status"
}

# ── wget ──

ccdc_net_wget() {
    local url="${1:-}"
    local output="${2:-}"
    if [[ -z "$url" ]]; then
        ccdc_log error "Usage: ccdc net wget <url> [output]"
        return 1
    fi
    [[ -z "$output" ]] && output="$(basename "$url")"

    ccdc_log info "Opening outbound for download..."
    ccdc_firewall_allow_internet 2>/dev/null || ccdc_log warn "Could not open outbound (firewall may not be configured)"

    ccdc_log info "Downloading: ${url}"
    local rc=0
    if command -v wget &>/dev/null; then
        wget -O "$output" "$url" || rc=$?
    elif command -v curl &>/dev/null; then
        curl -sLo "$output" "$url" || rc=$?
    else
        ccdc_log error "Neither wget nor curl found"
        rc=1
    fi

    ccdc_log info "Closing outbound..."
    ccdc_firewall_block_internet 2>/dev/null || true

    if [[ $rc -eq 0 ]]; then
        ccdc_log success "Downloaded to ${output}"
    else
        ccdc_log error "Download failed (exit code: ${rc})"
    fi
    return $rc
}

# ── curl ──

ccdc_net_curl() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        ccdc_log error "Usage: ccdc net curl <url>"
        return 1
    fi

    ccdc_log info "Opening outbound for fetch..."
    ccdc_firewall_allow_internet 2>/dev/null || ccdc_log warn "Could not open outbound (firewall may not be configured)"

    ccdc_log info "Fetching: ${url}"
    local rc=0
    if command -v curl &>/dev/null; then
        curl -sL "$url" || rc=$?
    elif command -v wget &>/dev/null; then
        wget -qO- "$url" || rc=$?
    else
        ccdc_log error "Neither curl nor wget found"
        rc=1
    fi

    ccdc_log info "Closing outbound..."
    ccdc_firewall_block_internet 2>/dev/null || true

    return $rc
}

# ── Handler ──

ccdc_net_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_net_usage
        return 0
    fi

    case "$cmd" in
        wget)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc net wget <url> [output]"; echo "Download file with auto firewall open/close"; return 0; }
            ccdc_net_wget "$@"
            ;;
        curl)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc net curl <url>"; echo "Quick fetch to stdout with auto firewall open/close"; return 0; }
            ccdc_net_curl "$@"
            ;;
        "")
            ccdc_net_usage
            ;;
        *)
            ccdc_log error "Unknown net command: ${cmd}"
            ccdc_net_usage
            return 1
            ;;
    esac
}
