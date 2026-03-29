#!/usr/bin/env bash
# ccdc-cli: OS, package manager, and firewall detection
# Depends on: common.sh (for ccdc_log)

# ── OS Detection (5-level fallback) ──

ccdc_detect_os() {
    local id="" id_like="" version=""

    # Level 1: /etc/os-release (freedesktop standard)
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID,,}"
        id_like="${ID_LIKE,,}"
        version="${VERSION_ID%%.*}"

    # Level 2: lsb_release command
    elif command -v lsb_release &>/dev/null; then
        id="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
        version="$(lsb_release -sr | cut -d. -f1)"

    # Level 3: /etc/lsb-release file
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck disable=SC1091
        . /etc/lsb-release
        id="${DISTRIB_ID,,}"
        version="${DISTRIB_RELEASE%%.*}"

    # Level 4: /etc/debian_version
    elif [[ -f /etc/debian_version ]]; then
        id="debian"
        version="$(cut -d. -f1 /etc/debian_version)"

    # Level 5: uname fallback
    else
        id="$(uname -s | tr '[:upper:]' '[:lower:]')"
        version="$(uname -r)"
    fi

    # Normalize known names
    case "$id" in
        "fedora linux") id="fedora" ;;
        "oracle linux server"|"ol") id="oracle" ;;
        "red hat"*|"redhat"*) id="rhel" ;;
    esac

    CCDC_OS="$id"
    CCDC_OS_VERSION="$version"

    # Derive OS family
    case "$id" in
        ubuntu|debian|kali|mint|pop)
            CCDC_OS_FAMILY="debian" ;;
        fedora|centos|rhel|rocky|alma|almalinux|oracle|ol)
            CCDC_OS_FAMILY="rhel" ;;
        opensuse*|sles|suse)
            CCDC_OS_FAMILY="suse" ;;
        arch|manjaro)
            CCDC_OS_FAMILY="arch" ;;
        *)
            # Try ID_LIKE for derivative distros
            if [[ "$id_like" == *"debian"* || "$id_like" == *"ubuntu"* ]]; then
                CCDC_OS_FAMILY="debian"
            elif [[ "$id_like" == *"rhel"* || "$id_like" == *"fedora"* || "$id_like" == *"centos"* ]]; then
                CCDC_OS_FAMILY="rhel"
            else
                CCDC_OS_FAMILY="unknown"
            fi
            ;;
    esac
}

# ── Package Manager Detection ──

ccdc_detect_pkg() {
    # Prefer modern over legacy
    if command -v apt &>/dev/null; then
        CCDC_PKG="apt"
    elif command -v dnf &>/dev/null; then
        CCDC_PKG="dnf"
    elif command -v yum &>/dev/null; then
        CCDC_PKG="yum"
    elif command -v zypper &>/dev/null; then
        CCDC_PKG="zypper"
    elif command -v pacman &>/dev/null; then
        CCDC_PKG="pacman"
    else
        CCDC_PKG="unknown"
    fi
}

# ── Firewall Backend Detection ──

ccdc_detect_fw() {
    CCDC_FW_AVAILABLE=()

    command -v firewall-cmd &>/dev/null && CCDC_FW_AVAILABLE+=("firewalld")
    command -v ufw &>/dev/null          && CCDC_FW_AVAILABLE+=("ufw")
    command -v nft &>/dev/null          && CCDC_FW_AVAILABLE+=("nft")
    command -v iptables &>/dev/null     && CCDC_FW_AVAILABLE+=("iptables")

    if [[ ${#CCDC_FW_AVAILABLE[@]} -eq 0 ]]; then
        CCDC_FW_BACKEND="none"
        return
    fi

    # Pick best based on OS family
    local preference
    if [[ "$CCDC_OS_FAMILY" == "rhel" ]]; then
        preference=(firewalld nft iptables ufw)
    else
        preference=(ufw nft iptables firewalld)
    fi

    for fw in "${preference[@]}"; do
        for avail in "${CCDC_FW_AVAILABLE[@]}"; do
            if [[ "$fw" == "$avail" ]]; then
                CCDC_FW_BACKEND="$fw"
                return
            fi
        done
    done

    CCDC_FW_BACKEND="none"
}

# ── Run All Detection ──

ccdc_detect_all() {
    ccdc_detect_os
    ccdc_detect_pkg
    ccdc_detect_fw

    ccdc_log info "OS:        ${CCDC_OS} ${CCDC_OS_VERSION} (${CCDC_OS_FAMILY})"
    ccdc_log info "Package:   ${CCDC_PKG}"
    ccdc_log info "Firewall:  ${CCDC_FW_BACKEND} (available: ${CCDC_FW_AVAILABLE[*]:-none})"
}
