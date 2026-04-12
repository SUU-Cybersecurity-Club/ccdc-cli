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
    echo "  wazuh-server         Install Wazuh manager (Linux)"
    echo "  wazuh-agent          Install Wazuh agent pointed at wazuh_server_ip"
    echo ""
    echo "Options:"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Examples:"
    echo "  ccdc siem snoopy"
    echo "  ccdc siem auditd"
    echo "  ccdc siem auditd --undo"
    echo "  ccdc config set wazuh_server_ip 10.0.0.5 && ccdc siem wazuh-agent"
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

# ── Wazuh shared helpers ──

_siem_wazuh_add_repo() {
    local snapshot_dir="$1"
    case "${CCDC_PKG:-}" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/wazuh.list ]]; then
                echo "apt" > "${snapshot_dir}/repo_added"
                ccdc_download https://packages.wazuh.com/key/GPG-KEY-WAZUH /tmp/wazuh.key || {
                    ccdc_log error "Failed to fetch Wazuh GPG key"
                    return 1
                }
                mkdir -p /usr/share/keyrings
                gpg --dearmor < /tmp/wazuh.key > /usr/share/keyrings/wazuh.gpg
                rm -f /tmp/wazuh.key
                echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
                    > /etc/apt/sources.list.d/wazuh.list
                apt-get update -qq 2>/dev/null || true
            fi
            ;;
        dnf|yum)
            if [[ ! -f /etc/yum.repos.d/wazuh.repo ]]; then
                echo "${CCDC_PKG}" > "${snapshot_dir}/repo_added"
                cat > /etc/yum.repos.d/wazuh.repo <<'EOF'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
            fi
            ;;
        *)
            ccdc_log error "Unsupported pkg manager for Wazuh: ${CCDC_PKG:-unknown}"
            return 1
            ;;
    esac
    return 0
}

_siem_wazuh_remove_repo() {
    local snapshot_dir="$1"
    local repo_added
    repo_added="$(cat "${snapshot_dir}/repo_added" 2>/dev/null)" || return 0
    case "$repo_added" in
        apt) rm -f /etc/apt/sources.list.d/wazuh.list /usr/share/keyrings/wazuh.gpg ;;
        dnf|yum) rm -f /etc/yum.repos.d/wazuh.repo ;;
    esac
}

# ── wazuh-server ──
# Prefers the official wazuh-docker single-node compose stack
# (manager + indexer + dashboard). Falls back to native wazuh-manager
# package install if docker/compose is unavailable.

CCDC_WAZUH_COMPOSE_DIR="${CCDC_WAZUH_COMPOSE_DIR:-/opt/wazuh-docker}"
CCDC_WAZUH_VERSION="${CCDC_WAZUH_VERSION:-v4.14.4}"
CCDC_WAZUH_COMPOSE_PROJECT="ccdc-wazuh"

_siem_wazuh_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
        return 0
    fi
    if command -v docker-compose &>/dev/null; then
        echo "docker-compose"
        return 0
    fi
    return 1
}

ccdc_siem_wazuh_server() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem wazuh-server)" || {
            ccdc_log error "No undo snapshot for siem wazuh-server"
            return 1
        }
        local install_method
        install_method="$(cat "${snapshot_dir}/install_method" 2>/dev/null)" || install_method="pkg"

        case "$install_method" in
            compose)
                local clone_dir clone_existed sysctl_existed compose_cmd
                clone_dir="$(cat "${snapshot_dir}/clone_dir" 2>/dev/null)" || clone_dir="$CCDC_WAZUH_COMPOSE_DIR"
                clone_existed="$(cat "${snapshot_dir}/clone_existed" 2>/dev/null)" || clone_existed="no"
                sysctl_existed="$(cat "${snapshot_dir}/sysctl_existed" 2>/dev/null)" || sysctl_existed="no"
                compose_cmd="$(_siem_wazuh_compose_cmd 2>/dev/null)" || compose_cmd="docker compose"

                if [[ -d "${clone_dir}/single-node" ]]; then
                    ccdc_log info "Tearing down compose stack (down -v)..."
                    (cd "${clone_dir}/single-node" && $compose_cmd -p "$CCDC_WAZUH_COMPOSE_PROJECT" down -v 2>/dev/null) || true
                fi
                if [[ "$clone_existed" == "no" && -d "$clone_dir" ]]; then
                    rm -rf "$clone_dir"
                fi
                if [[ "$sysctl_existed" == "no" ]]; then
                    rm -f /etc/sysctl.d/99-ccdc-wazuh.conf
                fi
                ;;
            *)
                local was_installed
                was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"
                systemctl stop wazuh-manager 2>/dev/null || true
                if [[ "$was_installed" == "no" ]]; then
                    systemctl disable wazuh-manager 2>/dev/null || true
                    ccdc_remove_pkg wazuh-manager 2>/dev/null || true
                    _siem_wazuh_remove_repo "$snapshot_dir"
                fi
                if [[ -f "${snapshot_dir}/ossec.conf" ]]; then
                    chattr -i "${snapshot_dir}/ossec.conf" 2>/dev/null || true
                    mkdir -p /var/ossec/etc
                    cp -a "${snapshot_dir}/ossec.conf" /var/ossec/etc/ossec.conf
                fi
                ;;
        esac

        ccdc_log success "siem wazuh-server restored (undo)"
        ccdc_undo_log "siem wazuh-server -- restored"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem wazuh-server)"

    # Layer 1: docker compose (preferred — official single-node stack)
    local compose_cmd
    if command -v docker &>/dev/null && docker info &>/dev/null && compose_cmd="$(_siem_wazuh_compose_cmd)"; then
        if ! command -v git &>/dev/null; then
            ccdc_install_pkg git || {
                ccdc_log error "git required for wazuh-docker clone"
                return 1
            }
        fi

        echo "compose" > "${snapshot_dir}/install_method"
        echo "$CCDC_WAZUH_COMPOSE_DIR" > "${snapshot_dir}/clone_dir"

        # ip_forward required for docker container networking;
        # vm.max_map_count required by the bundled wazuh-indexer
        local current_max_map
        current_max_map="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
        if [[ "$current_max_map" -ge 262144 ]]; then
            echo "yes" > "${snapshot_dir}/sysctl_existed"
        else
            echo "no" > "${snapshot_dir}/sysctl_existed"
            mkdir -p /etc/sysctl.d
            printf "net.ipv4.ip_forward=1\nvm.max_map_count=262144\n" > /etc/sysctl.d/99-ccdc-wazuh.conf
            sysctl -w vm.max_map_count=262144 >/dev/null 2>&1 || true
        fi
        sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
        systemctl restart docker 2>/dev/null || true

        if [[ -d "$CCDC_WAZUH_COMPOSE_DIR" ]]; then
            echo "yes" > "${snapshot_dir}/clone_existed"
            ccdc_log info "Reusing existing clone at ${CCDC_WAZUH_COMPOSE_DIR}"
        else
            echo "no" > "${snapshot_dir}/clone_existed"
            ccdc_log info "Cloning wazuh-docker ${CCDC_WAZUH_VERSION}..."
            if ! git clone --depth 1 -b "$CCDC_WAZUH_VERSION" \
                    https://github.com/wazuh/wazuh-docker.git "$CCDC_WAZUH_COMPOSE_DIR"; then
                ccdc_log error "git clone wazuh-docker failed"
                return 1
            fi
        fi

        local single_node_dir="${CCDC_WAZUH_COMPOSE_DIR}/single-node"
        if [[ ! -d "$single_node_dir" ]]; then
            ccdc_log error "single-node directory missing in clone: ${single_node_dir}"
            return 1
        fi

        cd "$single_node_dir" || return 1

        if [[ ! -d config/wazuh_indexer_ssl_certs ]] || [[ -z "$(ls -A config/wazuh_indexer_ssl_certs 2>/dev/null)" ]]; then
            ccdc_log info "Generating wazuh indexer TLS certificates..."
            $compose_cmd -f generate-indexer-certs.yml run --rm generator || \
                ccdc_log warn "Cert generator returned non-zero (often benign on re-runs)"
        fi

        ccdc_log info "Starting wazuh-docker stack via ${compose_cmd} (first run pulls ~5 GB)..."
        if ! $compose_cmd -p "$CCDC_WAZUH_COMPOSE_PROJECT" up -d; then
            ccdc_log error "docker compose up failed"
            return 1
        fi

        sleep 5
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${CCDC_WAZUH_COMPOSE_PROJECT}.*wazuh.manager"; then
            ccdc_log success "wazuh-docker stack running (manager + indexer + dashboard)"
            ccdc_log info "Dashboard: https://<host>  (admin / SecretPassword)"
        else
            ccdc_log warn "Compose up returned 0 but manager container not yet visible"
        fi

        ccdc_undo_log "siem wazuh-server -- snapshot at ${snapshot_dir}"
        ccdc_log success "Done. Undo: ccdc siem wazuh-server --undo"
        return 0
    fi

    # Layer 2: native package fallback
    ccdc_log info "docker compose not available; falling back to native wazuh-manager package"
    echo "pkg" > "${snapshot_dir}/install_method"

    if [[ -f /var/ossec/etc/ossec.conf ]] || systemctl list-unit-files 2>/dev/null | grep -q '^wazuh-manager'; then
        echo "yes" > "${snapshot_dir}/was_installed"
    else
        echo "no" > "${snapshot_dir}/was_installed"
    fi
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        ccdc_backup_file /var/ossec/etc/ossec.conf "$snapshot_dir"
    fi

    _siem_wazuh_add_repo "$snapshot_dir" || return 1

    if ! ccdc_install_pkg wazuh-manager; then
        ccdc_log error "Failed to install wazuh-manager"
        return 1
    fi

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now wazuh-manager 2>/dev/null || true

    if systemctl is-active wazuh-manager &>/dev/null; then
        ccdc_log success "wazuh-manager service is active"
    else
        ccdc_log warn "wazuh-manager installed but service not yet active"
    fi

    ccdc_undo_log "siem wazuh-server -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem wazuh-server --undo"
}

# ── wazuh-agent ──

ccdc_siem_wazuh_agent() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem wazuh-agent)" || {
            ccdc_log error "No undo snapshot for siem wazuh-agent"
            return 1
        }
        local was_installed
        was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"
        systemctl stop wazuh-agent 2>/dev/null || true
        if [[ "$was_installed" == "no" ]]; then
            systemctl disable wazuh-agent 2>/dev/null || true
            ccdc_remove_pkg wazuh-agent 2>/dev/null || true
            _siem_wazuh_remove_repo "$snapshot_dir"
        fi
        if [[ -f "${snapshot_dir}/ossec.conf" ]]; then
            chattr -i "${snapshot_dir}/ossec.conf" 2>/dev/null || true
            mkdir -p /var/ossec/etc
            cp -a "${snapshot_dir}/ossec.conf" /var/ossec/etc/ossec.conf
        fi
        ccdc_log success "siem wazuh-agent restored (undo)"
        ccdc_undo_log "siem wazuh-agent -- restored"
        return 0
    fi

    if [[ -z "${CCDC_WAZUH_IP:-}" ]]; then
        ccdc_log error "wazuh_server_ip not set. Run: ccdc config set wazuh_server_ip <ip>"
        return 1
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem wazuh-agent)"

    if [[ -f /var/ossec/etc/ossec.conf ]] || systemctl list-unit-files 2>/dev/null | grep -q '^wazuh-agent'; then
        echo "yes" > "${snapshot_dir}/was_installed"
    else
        echo "no" > "${snapshot_dir}/was_installed"
    fi
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        ccdc_backup_file /var/ossec/etc/ossec.conf "$snapshot_dir"
    fi

    _siem_wazuh_add_repo "$snapshot_dir" || return 1

    case "${CCDC_PKG:-}" in
        apt)
            WAZUH_MANAGER="${CCDC_WAZUH_IP}" ccdc_install_pkg wazuh-agent || {
                ccdc_log error "Failed to install wazuh-agent"
                return 1
            }
            ;;
        *)
            ccdc_install_pkg wazuh-agent || {
                ccdc_log error "Failed to install wazuh-agent"
                return 1
            }
            ;;
    esac

    # Always ensure ossec.conf points at the configured manager
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        sed -i "0,/<address>.*<\/address>/s||<address>${CCDC_WAZUH_IP}</address>|" /var/ossec/etc/ossec.conf
    fi

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now wazuh-agent 2>/dev/null || true

    if systemctl is-active wazuh-agent &>/dev/null; then
        ccdc_log success "wazuh-agent active, reporting to ${CCDC_WAZUH_IP}"
    else
        ccdc_log warn "wazuh-agent installed but service not yet active"
    fi

    ccdc_undo_log "siem wazuh-agent -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem wazuh-agent --undo"
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
        wazuh-server)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem wazuh-server"; echo "Install Wazuh manager"; return 0; }
            ccdc_siem_wazuh_server "$@"
            ;;
        wazuh-agent)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem wazuh-agent"; echo "Install Wazuh agent (uses wazuh_server_ip from config)"; return 0; }
            ccdc_siem_wazuh_agent "$@"
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
