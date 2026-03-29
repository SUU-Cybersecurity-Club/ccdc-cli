#!/usr/bin/env bash
# ccdc-cli: common helpers
# Sourced first — no dependencies on other lib files

# ── Color Constants ──
readonly CCDC_RED='\033[0;31m'
readonly CCDC_GREEN='\033[0;32m'
readonly CCDC_YELLOW='\033[1;33m'
readonly CCDC_BLUE='\033[0;34m'
readonly CCDC_CYAN='\033[0;36m'
readonly CCDC_BOLD='\033[1m'
readonly CCDC_NC='\033[0m'

# ── Logging ──

ccdc_log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%H:%M:%S')"
    local color prefix
    case "$level" in
        info)    color="$CCDC_BLUE";   prefix="[INFO]"  ;;
        warn)    color="$CCDC_YELLOW"; prefix="[WARN]"  ;;
        error)   color="$CCDC_RED";    prefix="[ERROR]" ;;
        success) color="$CCDC_GREEN";  prefix="[OK]"    ;;
        *)       color="$CCDC_NC";     prefix="[LOG]"   ;;
    esac
    echo -e "${color}${ts} ${prefix}${CCDC_NC} ${msg}"
    # Append to log file if set (without colors)
    if [[ -n "${CCDC_LOG:-}" && -d "$(dirname "$CCDC_LOG" 2>/dev/null)" ]]; then
        echo "${ts} ${prefix} ${msg}" >> "$CCDC_LOG" 2>/dev/null || true
    fi
}

ccdc_log_init() {
    if [[ -n "${CCDC_LOG:-}" ]]; then
        mkdir -p "$(dirname "$CCDC_LOG")" 2>/dev/null || true
    fi
}

# ── Root Check ──

ccdc_require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        ccdc_log error "This command requires root. Run with sudo."
        exit 1
    fi
}

# ── User Interaction ──

ccdc_confirm() {
    local prompt="${1:-Continue?}"
    if [[ "${CCDC_NO_PROMPT:-false}" == true ]]; then
        return 0
    fi
    echo -en "${CCDC_YELLOW}${prompt} [y/N]: ${CCDC_NC}"
    local reply
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Command Execution ──

ccdc_run() {
    if [[ "${CCDC_DRY_RUN:-false}" == true ]]; then
        ccdc_log info "[DRY RUN] Would run: $*"
        return 0
    fi
    if [[ "${CCDC_VERBOSE:-false}" == true ]]; then
        ccdc_log info "Running: $*"
    fi
    "$@"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        ccdc_log error "Command failed (exit $rc): $*"
    fi
    return $rc
}

# ── Package Management ──

ccdc_install_pkg() {
    local pkg="$1"
    ccdc_log info "Installing ${pkg}..."

    # Layer 1: package manager
    case "${CCDC_PKG:-}" in
        apt)    ccdc_run apt-get install -y "$pkg" && return 0 ;;
        dnf)    ccdc_run dnf install -y "$pkg" && return 0 ;;
        yum)    ccdc_run yum install -y "$pkg" && return 0 ;;
        zypper) ccdc_run zypper install -y "$pkg" && return 0 ;;
        pacman) ccdc_run pacman -S --noconfirm "$pkg" && return 0 ;;
    esac

    # Layer 2: bundled binary
    local bundled_deb="${CCDC_DIR}/bin/linux/${pkg}"*.deb
    local bundled_rpm="${CCDC_DIR}/bin/linux/${pkg}"*.rpm
    if [[ "${CCDC_OS_FAMILY:-}" == "debian" ]] && compgen -G "$bundled_deb" >/dev/null 2>&1; then
        ccdc_log info "Falling back to bundled .deb..."
        ccdc_run dpkg -i ${bundled_deb} && return 0
    elif [[ "${CCDC_OS_FAMILY:-}" == "rhel" ]] && compgen -G "$bundled_rpm" >/dev/null 2>&1; then
        ccdc_log info "Falling back to bundled .rpm..."
        ccdc_run rpm -ivh ${bundled_rpm} && return 0
    fi

    # Layer 3: manual extract
    if compgen -G "$bundled_deb" >/dev/null 2>&1; then
        ccdc_log warn "Attempting manual extract from .deb..."
        ccdc_run dpkg -x ${bundled_deb} / && return 0
    elif compgen -G "$bundled_rpm" >/dev/null 2>&1; then
        ccdc_log warn "Attempting manual extract from .rpm..."
        (cd / && rpm2cpio ${bundled_rpm} | cpio -idmv 2>/dev/null) && return 0
    fi

    ccdc_log error "Failed to install ${pkg}"
    return 1
}

ccdc_remove_pkg() {
    local pkg="$1"
    ccdc_log info "Removing ${pkg}..."
    case "${CCDC_PKG:-}" in
        apt)    ccdc_run apt-get remove -y "$pkg" ;;
        dnf)    ccdc_run dnf remove -y "$pkg" ;;
        yum)    ccdc_run yum remove -y "$pkg" ;;
        zypper) ccdc_run zypper remove -y "$pkg" ;;
        pacman) ccdc_run pacman -R --noconfirm "$pkg" ;;
        *)      ccdc_log error "Unknown package manager"; return 1 ;;
    esac
}

# ── File Operations ──

ccdc_backup_file() {
    local src="$1"
    local dest_dir="$2"
    if [[ ! -f "$src" ]]; then
        return 0
    fi
    mkdir -p "$dest_dir"
    cp -a "$src" "$dest_dir/"
    # Best-effort immutable attribute
    chattr +i "${dest_dir}/$(basename "$src")" 2>/dev/null || true
}

ccdc_restore_file() {
    local backup_path="$1"
    local original_path="$2"
    if [[ ! -f "$backup_path" ]]; then
        ccdc_log error "Backup not found: ${backup_path}"
        return 1
    fi
    # Remove immutable if set
    chattr -i "$backup_path" 2>/dev/null || true
    chattr -i "$original_path" 2>/dev/null || true
    cp -a "$backup_path" "$original_path"
}

ccdc_make_immutable() {
    local path="$1"
    chattr +i "$path" 2>/dev/null || true
}

# ── Network ──

ccdc_download() {
    local url="$1"
    local output="$2"
    if command -v wget &>/dev/null; then
        wget -q -O "$output" "$url" && return 0
    fi
    if command -v curl &>/dev/null; then
        curl -sL -o "$output" "$url" && return 0
    fi
    ccdc_log error "Neither wget nor curl available"
    return 1
}

# ── Help ──

ccdc_usage() {
    echo -e "${CCDC_BOLD}ccdc-cli${CCDC_NC} — CCDC competition hardening toolkit"
    echo ""
    echo -e "${CCDC_BOLD}Usage:${CCDC_NC} ccdc <category> <command> [options]"
    echo ""
    echo -e "${CCDC_BOLD}Categories:${CCDC_NC}"
    echo "  passwd    (pw)     Password management"
    echo "  backup    (bak)    Backup and restore"
    echo "  discover  (disc)   System discovery and recon"
    echo "  service   (svc)    Service management"
    echo "  firewall  (fw)     Firewall configuration"
    echo "  harden    (hrd)    System hardening"
    echo "  siem               SIEM and monitoring setup"
    echo "  install   (inst)   Package and tool installation"
    echo "  net                Firewall-aware downloads"
    echo "  config    (cfg)    Persistent configuration"
    echo "  comp-start         Run full competition checklist"
    echo ""
    echo -e "${CCDC_BOLD}Global Flags:${CCDC_NC}"
    echo "  --help, -h         Show help"
    echo "  --undo             Undo last run of a command"
    echo "  --no-prompt        Skip confirmation prompts"
    echo "  --dry-run          Show what would be done"
    echo "  --verbose, -v      Verbose output"
    echo ""
    echo -e "${CCDC_BOLD}Tab Completion:${CCDC_NC}"
    echo "  sudo ./ccdc.sh --setup-completions    Install bash tab completion"
    echo ""
    echo "Run 'ccdc <category> --help' for command-specific help."
}
