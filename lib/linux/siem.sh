#!/usr/bin/env bash
# ccdc-cli: SIEM and monitoring module
# Depends on: common.sh, detect.sh, config.sh, undo.sh

# ── Usage ──

ccdc_siem_usage() {
    echo -e "${CCDC_BOLD}ccdc siem${CCDC_NC} — SIEM and monitoring setup"
    echo ""
    echo "Commands:"
    echo "  snoopy               Install snoopy command logger (Linux)"
    echo "  auditd               Deploy ccdc auditd ruleset (Linux)"
    echo "  sysmon               Install Sysmon (Windows only)"
    echo ""
    echo "Options:"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Examples:"
    echo "  ccdc siem snoopy"
    echo "  ccdc siem auditd"
    echo "  ccdc siem auditd --undo"
}

# ── snoopy ──

ccdc_siem_snoopy() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem snoopy)" || {
            ccdc_log error "No undo snapshot for siem snoopy"
            return 1
        }
        local was_installed
        was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"
        if [[ "$was_installed" == "no" ]]; then
            ccdc_remove_pkg snoopy 2>/dev/null || true
        fi
        # Restore /etc/ld.so.preload (or remove if it didn't exist)
        if [[ -f "${snapshot_dir}/ld.so.preload" ]]; then
            chattr -i "${snapshot_dir}/ld.so.preload" 2>/dev/null || true
            cp -a "${snapshot_dir}/ld.so.preload" /etc/ld.so.preload
        else
            # Best-effort: strip snoopy line if file exists
            if [[ -f /etc/ld.so.preload ]]; then
                sed -i '/snoopy/d' /etc/ld.so.preload
            fi
        fi
        ccdc_log success "siem snoopy restored (undo)"
        ccdc_undo_log "siem snoopy -- restored"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem snoopy)"

    if command -v snoopy &>/dev/null || grep -q snoopy /etc/ld.so.preload 2>/dev/null; then
        echo "yes" > "${snapshot_dir}/was_installed"
    else
        echo "no" > "${snapshot_dir}/was_installed"
    fi
    if [[ -f /etc/ld.so.preload ]]; then
        ccdc_backup_file /etc/ld.so.preload "$snapshot_dir"
    fi

    if [[ "${CCDC_OS_FAMILY:-}" == "rhel" ]]; then
        if ! ccdc_install_pkg snoopy; then
            ccdc_log warn "snoopy not in base repos on RHEL family. Enable EPEL: 'dnf install -y epel-release' then retry."
            ccdc_undo_log "siem snoopy -- install failed (EPEL?), snapshot at ${snapshot_dir}"
            return 0
        fi
    else
        ccdc_install_pkg snoopy || {
            ccdc_log error "Failed to install snoopy"
            return 1
        }
    fi

    # Verify
    if grep -q snoopy /etc/ld.so.preload 2>/dev/null; then
        ccdc_log success "snoopy active via /etc/ld.so.preload"
    elif command -v snoopy &>/dev/null; then
        ccdc_log success "snoopy installed"
    else
        ccdc_log warn "snoopy installed but preload hook not detected"
    fi

    ccdc_undo_log "siem snoopy -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem snoopy --undo"
}

# ── auditd ──

_siem_auditd_reload() {
    if command -v augenrules &>/dev/null; then
        augenrules --load 2>/dev/null || true
    fi
    if command -v systemctl &>/dev/null; then
        systemctl restart auditd 2>/dev/null || service auditd restart 2>/dev/null || true
    else
        service auditd restart 2>/dev/null || true
    fi
}

ccdc_siem_auditd() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem auditd)" || {
            ccdc_log error "No undo snapshot for siem auditd"
            return 1
        }
        local was_present
        was_present="$(cat "${snapshot_dir}/was_present" 2>/dev/null)" || was_present="no"
        if [[ "$was_present" == "yes" && -f "${snapshot_dir}/99-ccdc.rules" ]]; then
            chattr -i "${snapshot_dir}/99-ccdc.rules" 2>/dev/null || true
            cp -a "${snapshot_dir}/99-ccdc.rules" /etc/audit/rules.d/99-ccdc.rules
        else
            rm -f /etc/audit/rules.d/99-ccdc.rules
        fi
        _siem_auditd_reload
        ccdc_log success "auditd ccdc rules restored (undo)"
        ccdc_undo_log "siem auditd -- restored"
        return 0
    fi

    local rules_src="${CCDC_DIR}/bin/audit/99-ccdc.rules"
    if [[ ! -f "$rules_src" ]]; then
        ccdc_log error "Bundled rules file missing: ${rules_src}"
        return 1
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem auditd)"

    if [[ -f /etc/audit/rules.d/99-ccdc.rules ]]; then
        echo "yes" > "${snapshot_dir}/was_present"
        ccdc_backup_file /etc/audit/rules.d/99-ccdc.rules "$snapshot_dir"
    else
        echo "no" > "${snapshot_dir}/was_present"
    fi

    # Ensure auditd is installed (usually pre-installed)
    if ! command -v auditctl &>/dev/null; then
        ccdc_install_pkg audit || ccdc_install_pkg auditd || {
            ccdc_log error "Failed to install auditd"
            return 1
        }
    fi

    mkdir -p /etc/audit/rules.d
    install -m 0640 "$rules_src" /etc/audit/rules.d/99-ccdc.rules
    ccdc_log info "Deployed 99-ccdc.rules to /etc/audit/rules.d/"

    _siem_auditd_reload

    if auditctl -l 2>/dev/null | grep -q ccdc; then
        ccdc_log success "auditd loaded ccdc rules"
    else
        ccdc_log warn "Rules deployed but not yet visible in auditctl -l (may need reboot)"
    fi

    ccdc_undo_log "siem auditd -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem auditd --undo"
}

# ── sysmon (Windows only stub) ──

ccdc_siem_sysmon() {
    ccdc_log info "sysmon is a Windows-only command. Run 'ccdc siem sysmon' from a Windows host."
    return 0
}

# ── Handler ──

ccdc_siem_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_siem_usage
        return 0
    fi

    case "$cmd" in
        snoopy)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem snoopy"; echo "Install snoopy command logger"; return 0; }
            ccdc_siem_snoopy "$@"
            ;;
        auditd)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem auditd"; echo "Deploy ccdc auditd ruleset"; return 0; }
            ccdc_siem_auditd "$@"
            ;;
        sysmon)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem sysmon"; echo "Install Sysmon (Windows only)"; return 0; }
            ccdc_siem_sysmon "$@"
            ;;
        "")
            ccdc_siem_usage
            ;;
        *)
            ccdc_log error "Unknown siem command: ${cmd}"
            ccdc_siem_usage
            return 1
            ;;
    esac
}
