#!/usr/bin/env bash
# ccdc-cli: 3-layer undo framework
# Depends on: common.sh, config.sh (for CCDC_UNDO_DIR)

# ══════════════════════════════════════════
# Layer 1: Original Baseline
# Created once during 'config init', never overwritten
# ══════════════════════════════════════════

ccdc_undo_create_baseline() {
    local base="${CCDC_UNDO_DIR}/original"

    # Skip if baseline already exists (immutable files from prior run)
    if [[ -f "${base}/.created" ]]; then
        ccdc_log info "Baseline already exists at ${base} -- skipping"
        return 0
    fi

    mkdir -p "$base"
    # Remove immutable in case of partial prior run
    chattr -i -R "${base}" 2>/dev/null || true
    ccdc_log info "Creating initial baseline snapshot..."

    # Firewall rules (capture from all available backends)
    iptables-save > "${base}/iptables.rules" 2>/dev/null || true
    ip6tables-save > "${base}/ip6tables.rules" 2>/dev/null || true
    command -v nft &>/dev/null && nft list ruleset > "${base}/nft.rules" 2>/dev/null || true
    command -v ufw &>/dev/null && ufw status verbose > "${base}/ufw.status" 2>/dev/null || true
    command -v firewall-cmd &>/dev/null && firewall-cmd --list-all-zones > "${base}/firewalld.rules" 2>/dev/null || true

    # Critical config files
    [[ -f /etc/shadow ]]          && cp -a /etc/shadow "${base}/shadow.bak" 2>/dev/null || true
    [[ -f /etc/passwd ]]          && cp -a /etc/passwd "${base}/passwd.bak" 2>/dev/null || true
    [[ -f /etc/group ]]           && cp -a /etc/group "${base}/group.bak" 2>/dev/null || true
    [[ -f /etc/ssh/sshd_config ]] && cp -a /etc/ssh/sshd_config "${base}/sshd_config.bak" 2>/dev/null || true
    [[ -f /etc/crontab ]]         && cp -a /etc/crontab "${base}/crontab.bak" 2>/dev/null || true

    # User crontabs
    mkdir -p "${base}/crontabs"
    while IFS=: read -r username _ _ _ _ _ shell; do
        [[ "$shell" == */nologin || "$shell" == */false ]] && continue
        crontab -l -u "$username" > "${base}/crontabs/${username}.cron" 2>/dev/null || true
    done < /etc/passwd

    # Service list
    systemctl list-unit-files --type=service > "${base}/services.list" 2>/dev/null || true

    # Mark as created BEFORE making immutable
    touch "${base}/.created"
    ccdc_undo_log "baseline created at ${base}"

    # Make baseline immutable
    chattr +i -R "${base}" 2>/dev/null || true

    ccdc_log success "Baseline snapshot saved to ${base}"
}

# ══════════════════════════════════════════
# Layer 2: Per-Command Snapshots
# Created before every destructive command
# ══════════════════════════════════════════

ccdc_undo_snapshot_create() {
    local category="$1"
    local command="$2"
    local ts
    ts="$(date +%Y-%m-%d_%H%M%S)"
    local dir="${CCDC_UNDO_DIR}/${category}/${command}/${ts}"
    mkdir -p "$dir"
    echo "$dir"
}

ccdc_undo_snapshot_latest() {
    local category="$1"
    local command="$2"
    local dir="${CCDC_UNDO_DIR}/${category}/${command}"
    if [[ ! -d "$dir" ]]; then
        return 1
    fi
    local latest
    latest="$(ls -1t "$dir" 2>/dev/null | head -1)"
    if [[ -z "$latest" ]]; then
        return 1
    fi
    echo "${dir}/${latest}"
}

ccdc_undo_snapshot_restore() {
    local category="$1"
    local command="$2"
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_latest "$category" "$command")" || {
        ccdc_log error "No snapshot found for ${category}/${command}"
        return 1
    }
    ccdc_log info "Restoring from snapshot: ${snapshot_dir}"
    # Each command's _undo() function handles the actual restore logic
    # This just provides the path
    echo "$snapshot_dir"
}

# ══════════════════════════════════════════
# Layer 3: Undo Log (append-only)
# ══════════════════════════════════════════

ccdc_undo_log() {
    local msg="$1"
    mkdir -p "${CCDC_UNDO_DIR}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "${CCDC_UNDO_DIR}/undo.log"
}

ccdc_undo_log_show() {
    if [[ -f "${CCDC_UNDO_DIR}/undo.log" ]]; then
        echo -e "${CCDC_BOLD}Undo Log:${CCDC_NC}"
        cat "${CCDC_UNDO_DIR}/undo.log"
    else
        ccdc_log info "No undo log yet. Run some commands first."
    fi
}

# ══════════════════════════════════════════
# Core Wrapper: ccdc_undo_run
# Every destructive command uses this
# ══════════════════════════════════════════

ccdc_undo_run() {
    local category="$1"
    local command="$2"
    local backup_func="$3"
    local action_func="$4"
    shift 4

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create "$category" "$command")"

    {
        "$backup_func" "$snapshot_dir" "$@"
        "$action_func" "$@"
    } || {
        ccdc_log error "Command failed. Restoring from snapshot..."
        "$backup_func" "$snapshot_dir" --restore 2>/dev/null || true
        return 1
    }

    ccdc_undo_log "${category} ${command} -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc ${category} ${command} --undo"
}

# ── Undo Handler ──

ccdc_undo_handler() {
    local cmd="${1:-}"
    case "$cmd" in
        log|show)
            ccdc_undo_log_show
            ;;
        "")
            ccdc_undo_log_show
            ;;
        *)
            ccdc_log error "Unknown undo command: ${cmd}"
            echo "Usage: ccdc undo log"
            return 1
            ;;
    esac
}
