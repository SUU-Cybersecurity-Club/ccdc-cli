#!/usr/bin/env bash
# ccdc-cli: service management module
# Depends on: common.sh, detect.sh, config.sh, undo.sh

# ── Usage ──

ccdc_service_usage() {
    echo -e "${CCDC_BOLD}ccdc service${CCDC_NC} — Service management"
    echo ""
    echo "Commands:"
    echo "  list (ls)            List running services"
    echo "  stop <name>          Stop a service"
    echo "  disable <name>       Stop and disable a service"
    echo "  enable <name>        Enable and start a service"
    echo "  cockpit              Stop, disable, and remove Cockpit"
    echo ""
    echo "Options:"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Examples:"
    echo "  ccdc svc ls                     List running services"
    echo "  ccdc svc stop cups              Stop CUPS print service"
    echo "  ccdc svc disable cups           Stop and disable CUPS"
    echo "  ccdc svc enable sshd            Enable and start SSH"
    echo "  ccdc svc cockpit                Remove Cockpit"
    echo "  ccdc svc stop cups --undo       Re-start cups"
}

# ── List ──

ccdc_service_list() {
    ccdc_log info "Running services:"
    echo ""
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null || \
        service --status-all 2>/dev/null || echo "(no systemctl/service found)"
}

# ── Stop ──

ccdc_service_stop() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        ccdc_log error "Usage: ccdc service stop <name>"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest service "stop-${name}")" || {
            ccdc_log error "No undo snapshot for service stop ${name}"
            return 1
        }
        local was_active
        was_active="$(cat "${snapshot_dir}/was_active" 2>/dev/null)" || was_active="active"
        if [[ "$was_active" == "active" ]]; then
            systemctl start "$name"
            ccdc_log success "Service ${name} started (undo)"
        else
            ccdc_log info "Service ${name} was not active before, skipping start"
        fi
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create service "stop-${name}")"
    systemctl is-active "$name" 2>/dev/null > "${snapshot_dir}/was_active" || echo "inactive" > "${snapshot_dir}/was_active"

    systemctl stop "$name"
    ccdc_log success "Service ${name} stopped"
    ccdc_undo_log "service stop ${name} -- snapshot at ${snapshot_dir}"
}

# ── Disable ──

ccdc_service_disable() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        ccdc_log error "Usage: ccdc service disable <name>"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest service "disable-${name}")" || {
            ccdc_log error "No undo snapshot for service disable ${name}"
            return 1
        }
        local was_enabled was_active
        was_enabled="$(cat "${snapshot_dir}/was_enabled" 2>/dev/null)" || was_enabled="enabled"
        was_active="$(cat "${snapshot_dir}/was_active" 2>/dev/null)" || was_active="active"
        if [[ "$was_enabled" == "enabled" ]]; then
            systemctl enable "$name"
        fi
        if [[ "$was_active" == "active" ]]; then
            systemctl start "$name"
        fi
        ccdc_log success "Service ${name} re-enabled and started (undo)"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create service "disable-${name}")"
    systemctl is-enabled "$name" 2>/dev/null > "${snapshot_dir}/was_enabled" || echo "disabled" > "${snapshot_dir}/was_enabled"
    systemctl is-active "$name" 2>/dev/null > "${snapshot_dir}/was_active" || echo "inactive" > "${snapshot_dir}/was_active"

    systemctl stop "$name" 2>/dev/null || true
    systemctl disable "$name"
    ccdc_log success "Service ${name} stopped and disabled"
    ccdc_undo_log "service disable ${name} -- snapshot at ${snapshot_dir}"
}

# ── Enable ──

ccdc_service_enable() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        ccdc_log error "Usage: ccdc service enable <name>"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest service "enable-${name}")" || {
            ccdc_log error "No undo snapshot for service enable ${name}"
            return 1
        }
        local was_enabled was_active
        was_enabled="$(cat "${snapshot_dir}/was_enabled" 2>/dev/null)" || was_enabled="disabled"
        was_active="$(cat "${snapshot_dir}/was_active" 2>/dev/null)" || was_active="inactive"
        if [[ "$was_enabled" != "enabled" ]]; then
            systemctl disable "$name"
        fi
        if [[ "$was_active" != "active" ]]; then
            systemctl stop "$name"
        fi
        ccdc_log success "Service ${name} restored to previous state (undo)"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create service "enable-${name}")"
    systemctl is-enabled "$name" 2>/dev/null > "${snapshot_dir}/was_enabled" || echo "disabled" > "${snapshot_dir}/was_enabled"
    systemctl is-active "$name" 2>/dev/null > "${snapshot_dir}/was_active" || echo "inactive" > "${snapshot_dir}/was_active"

    systemctl enable "$name"
    systemctl start "$name"
    ccdc_log success "Service ${name} enabled and started"
    ccdc_undo_log "service enable ${name} -- snapshot at ${snapshot_dir}"
}

# ── Cockpit ──

ccdc_service_cockpit() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest service cockpit)" || {
            ccdc_log error "No undo snapshot for service cockpit"
            return 1
        }
        local was_installed
        was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"
        if [[ "$was_installed" == "yes" ]]; then
            ccdc_log info "Re-installing cockpit..."
            ccdc_install_pkg cockpit 2>/dev/null || true
            systemctl unmask cockpit cockpit.socket 2>/dev/null || true
            systemctl enable --now cockpit.socket 2>/dev/null || true
            ccdc_log success "Cockpit re-installed (undo)"
        else
            ccdc_log info "Cockpit was not installed before, skipping"
        fi
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create service cockpit)"

    # Check if cockpit is installed
    local was_installed="no"
    if command -v cockpit-ws &>/dev/null || systemctl list-unit-files | grep -q cockpit; then
        was_installed="yes"
    fi
    echo "$was_installed" > "${snapshot_dir}/was_installed"

    ccdc_log info "Stopping and disabling Cockpit..."
    systemctl stop cockpit cockpit.socket 2>/dev/null || true
    systemctl disable cockpit cockpit.socket 2>/dev/null || true
    systemctl mask cockpit cockpit.socket 2>/dev/null || true

    ccdc_log info "Removing Cockpit package..."
    ccdc_remove_pkg cockpit 2>/dev/null || true

    # Block port 9090 if firewall module is loaded
    if type ccdc_firewall_handler &>/dev/null; then
        ccdc_firewall_block_in 9090 tcp 2>/dev/null || true
    fi

    ccdc_log success "Cockpit stopped, disabled, masked, and removed"
    ccdc_undo_log "service cockpit -- removed, snapshot at ${snapshot_dir}"
}

# ── Handler ──

ccdc_service_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_service_usage
        return 0
    fi

    case "$cmd" in
        list|ls)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc service list"; echo "List running services"; return 0; }
            ccdc_service_list
            ;;
        stop)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc service stop <name>"; return 0; }
            ccdc_service_stop "$@"
            ;;
        disable)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc service disable <name>"; echo "Stop and disable a service"; return 0; }
            ccdc_service_disable "$@"
            ;;
        enable)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc service enable <name>"; echo "Enable and start a service"; return 0; }
            ccdc_service_enable "$@"
            ;;
        cockpit)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc service cockpit"; echo "Stop, disable, and remove Cockpit"; return 0; }
            ccdc_service_cockpit "$@"
            ;;
        "")
            ccdc_service_usage
            ;;
        *)
            ccdc_log error "Unknown service command: ${cmd}"
            ccdc_service_usage
            return 1
            ;;
    esac
}
