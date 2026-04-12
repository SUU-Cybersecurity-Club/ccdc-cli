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
    echo "  suricata             Install Suricata IDS (Linux + Windows)"
    echo "  zeek                 Install Zeek network monitor (Linux)"
    echo "  docker               Install Docker engine (Linux)"
    echo "  wazuh-archives       Enable full forensics logging (Linux)"
    echo ""
    echo "Options:"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Examples:"
    echo "  ccdc siem snoopy"
    echo "  ccdc siem auditd"
    echo "  ccdc siem auditd --undo"
    echo "  ccdc siem suricata"
    echo "  ccdc siem docker && ccdc siem wazuh-server"
    echo "  ccdc siem wazuh-archives"
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
        # Undo wazuh-archives first (auto-enabled during install)
        ccdc_siem_wazuh_archives 2>/dev/null || true

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

        # Auto-enable full forensics logging
        ccdc_log info "Enabling wazuh-archives (full forensics logging)..."
        ccdc_siem_wazuh_archives
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

    # Auto-enable full forensics logging
    ccdc_log info "Enabling wazuh-archives (full forensics logging)..."
    ccdc_siem_wazuh_archives
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
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now wazuh-agent 2>/dev/null || true

    # Wait for agent to connect (manager may still be initializing)
    local retries=0
    while [[ $retries -lt 5 ]] && ! systemctl is-active wazuh-agent &>/dev/null; do
        sleep 2
        retries=$((retries + 1))
    done

    if systemctl is-active wazuh-agent &>/dev/null; then
        ccdc_log success "wazuh-agent active, reporting to ${CCDC_WAZUH_IP}"
    elif [[ -f /var/ossec/etc/ossec.conf ]]; then
        ccdc_log info "wazuh-agent installed and configured (service may need manager to be reachable)"
    else
        ccdc_log warn "wazuh-agent installed but service not yet active"
    fi

    ccdc_undo_log "siem wazuh-agent -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem wazuh-agent --undo"
}

# ── Shared: interface detection ──

_siem_detect_iface() {
    local iface
    iface="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
    if [[ -z "$iface" ]]; then
        iface="eth0"
        ccdc_log warn "Could not detect default interface, falling back to eth0"
    fi
    echo "$iface"
}

# ── docker ──

ccdc_siem_docker() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem docker)" || {
            ccdc_log error "No undo snapshot for siem docker"
            return 1
        }
        local was_installed was_enabled
        was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"
        was_enabled="$(cat "${snapshot_dir}/was_enabled" 2>/dev/null)" || was_enabled="no"
        systemctl stop docker 2>/dev/null || true
        if [[ "$was_enabled" == "no" ]]; then
            systemctl disable docker 2>/dev/null || true
        fi
        if [[ "$was_installed" == "no" ]]; then
            ccdc_remove_pkg docker-ce 2>/dev/null || ccdc_remove_pkg docker.io 2>/dev/null || ccdc_remove_pkg docker 2>/dev/null || true
            # Only remove compose plugin if it's actually installed
            if dpkg -l docker-compose-plugin &>/dev/null || rpm -q docker-compose-plugin &>/dev/null; then
                ccdc_remove_pkg docker-compose-plugin 2>/dev/null || true
            fi
        fi
        ccdc_log success "siem docker restored (undo)"
        ccdc_undo_log "siem docker -- restored"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem docker)"

    if command -v docker &>/dev/null; then
        echo "yes" > "${snapshot_dir}/was_installed"
    else
        echo "no" > "${snapshot_dir}/was_installed"
    fi
    if systemctl is-enabled docker &>/dev/null; then
        echo "yes" > "${snapshot_dir}/was_enabled"
    else
        echo "no" > "${snapshot_dir}/was_enabled"
    fi

    # Install docker -- skip if already present, then try distro pkg, Docker CE repo, get.docker.com
    local installed=false
    if command -v docker &>/dev/null; then
        ccdc_log info "Docker already installed"
        installed=true
    fi

    if [[ "$installed" == false ]]; then
        case "${CCDC_PKG:-}" in
            apt)
                ccdc_install_pkg docker.io && installed=true
                ;;
            dnf|yum)
                # Check if docker-ce repo is already configured (from prior install)
                if rpm -q docker-ce &>/dev/null 2>&1; then
                    installed=true
                else
                    ccdc_install_pkg docker 2>/dev/null && installed=true
                    if [[ "$installed" == false ]]; then
                        ccdc_install_pkg moby-engine 2>/dev/null && installed=true
                    fi
                    if [[ "$installed" == false ]]; then
                        ccdc_log info "Adding Docker CE repo..."
                        "${CCDC_PKG}" config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
                            "${CCDC_PKG}" config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
                        ccdc_install_pkg docker-ce 2>/dev/null && installed=true
                    fi
                fi
                ;;
        esac
    fi

    # Last resort: get.docker.com convenience script
    if [[ "$installed" == false ]]; then
        ccdc_log info "Trying get.docker.com install script..."
        if command -v curl &>/dev/null; then
            curl -fsSL https://get.docker.com | sh 2>/dev/null && installed=true
        elif command -v wget &>/dev/null; then
            wget -qO- https://get.docker.com | sh 2>/dev/null && installed=true
        fi
    fi

    if [[ "$installed" == false ]]; then
        ccdc_log error "Failed to install docker"
        return 1
    fi

    # Best-effort compose plugin (only if docker-ce is installed, not docker.io)
    if rpm -q docker-ce &>/dev/null 2>&1 || rpm -q docker-ce-cli &>/dev/null 2>&1; then
        ccdc_install_pkg docker-compose-plugin 2>/dev/null || true
    fi

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true

    # Wait for docker daemon to be ready (can take a few seconds after fresh install)
    local retries=0
    while [[ $retries -lt 10 ]] && ! docker info &>/dev/null; do
        sleep 3
        systemctl start docker 2>/dev/null || true
        retries=$((retries + 1))
    done

    if docker info &>/dev/null; then
        ccdc_log success "Docker engine running"
    else
        ccdc_log warn "Docker installed but 'docker info' failed (may need reboot)"
    fi

    ccdc_undo_log "siem docker -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem docker --undo"
}

# ── suricata ──

ccdc_siem_suricata() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem suricata)" || {
            ccdc_log error "No undo snapshot for siem suricata"
            return 1
        }
        local was_installed
        was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"

        systemctl stop suricata 2>/dev/null || true
        systemctl disable suricata 2>/dev/null || true

        # Restore suricata.yaml
        if [[ -f "${snapshot_dir}/suricata.yaml" ]]; then
            chattr -i "${snapshot_dir}/suricata.yaml" 2>/dev/null || true
            cp -a "${snapshot_dir}/suricata.yaml" /etc/suricata/suricata.yaml
        fi

        # Restore ossec.conf
        if [[ -f "${snapshot_dir}/ossec.conf" ]]; then
            chattr -i "${snapshot_dir}/ossec.conf" 2>/dev/null || true
            cp -a "${snapshot_dir}/ossec.conf" /var/ossec/etc/ossec.conf
            # Restart wazuh so restored config takes effect
            systemctl restart wazuh-agent 2>/dev/null || systemctl restart wazuh-manager 2>/dev/null || true
        fi

        if [[ "$was_installed" == "no" ]]; then
            ccdc_remove_pkg suricata 2>/dev/null || true
        fi

        ccdc_log success "siem suricata restored (undo)"
        ccdc_undo_log "siem suricata -- restored"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem suricata)"

    if command -v suricata &>/dev/null; then
        echo "yes" > "${snapshot_dir}/was_installed"
    else
        echo "no" > "${snapshot_dir}/was_installed"
    fi

    # Backup existing configs
    [[ -f /etc/suricata/suricata.yaml ]] && ccdc_backup_file /etc/suricata/suricata.yaml "$snapshot_dir"
    [[ -f /var/ossec/etc/ossec.conf ]] && ccdc_backup_file /var/ossec/etc/ossec.conf "$snapshot_dir"

    # Install -- try base repos first, then add OISF repo
    local installed=false
    ccdc_install_pkg suricata 2>/dev/null && installed=true
    if [[ "$installed" == false ]]; then
        case "${CCDC_PKG:-}" in
            apt)
                ccdc_log info "Adding Suricata PPA..."
                add-apt-repository -y ppa:oisf/suricata-stable 2>/dev/null || true
                apt-get update -qq 2>/dev/null || true
                ccdc_install_pkg suricata && installed=true
                ;;
            dnf|yum)
                ccdc_log info "Adding Suricata COPR repo..."
                "${CCDC_PKG}" install -y epel-release 2>/dev/null || true
                "${CCDC_PKG}" copr enable -y @oisf/suricata-7.0 2>/dev/null || true
                ccdc_install_pkg suricata && installed=true
                ;;
        esac
    fi
    if [[ "$installed" == false ]]; then
        ccdc_log error "Failed to install suricata"
        return 1
    fi

    # Detect interface and local network
    local iface local_cidr
    iface="$(_siem_detect_iface)"
    local_cidr="$(ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4; exit}')"
    [[ -z "$local_cidr" ]] && local_cidr="10.0.0.0/8"

    # Configure suricata.yaml
    if [[ -f /etc/suricata/suricata.yaml ]]; then
        # Set af-packet interface
        sed -i "0,/- interface: .*/s//- interface: ${iface}/" /etc/suricata/suricata.yaml
        ccdc_log info "Suricata af-packet interface set to ${iface}"

        # Set HOME_NET to local network
        sed -i "s|HOME_NET:.*|HOME_NET: \"[${local_cidr}]\"|" /etc/suricata/suricata.yaml
        ccdc_log info "Suricata HOME_NET set to ${local_cidr}"
    fi

    # RHEL: also update /etc/sysconfig/suricata if it exists
    if [[ -f /etc/sysconfig/suricata ]]; then
        sed -i "s/eth0/${iface}/g" /etc/sysconfig/suricata
        ccdc_log info "Updated /etc/sysconfig/suricata interface"
    fi

    # Download/update rules
    if command -v suricata-update &>/dev/null; then
        ccdc_log info "Updating Suricata rules..."
        suricata-update 2>/dev/null || ccdc_log warn "suricata-update returned non-zero"
    fi

    # Enable and start (restart after rule update to load new rules)
    systemctl enable suricata 2>/dev/null || true
    systemctl restart suricata 2>/dev/null || systemctl start suricata 2>/dev/null || true

    # Wazuh integration: append eve.json localfile to ossec.conf
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        if ! grep -q 'eve.json' /var/ossec/etc/ossec.conf 2>/dev/null; then
            sed -i '/<\/ossec_config>/i \
  <localfile>\
    <log_format>json<\/log_format>\
    <location>\/var\/log\/suricata\/eve.json<\/location>\
  <\/localfile>' /var/ossec/etc/ossec.conf
            ccdc_log info "Added eve.json localfile to ossec.conf"
        fi
        # Restart wazuh so new ossec.conf takes effect
        systemctl restart wazuh-agent 2>/dev/null || systemctl restart wazuh-manager 2>/dev/null || true
    fi

    # Validate config
    if suricata -T -c /etc/suricata/suricata.yaml &>/dev/null; then
        ccdc_log success "Suricata config validates OK"
    else
        ccdc_log warn "Suricata config validation failed -- check /etc/suricata/suricata.yaml"
    fi

    if systemctl is-active suricata &>/dev/null; then
        ccdc_log success "Suricata IDS running on interface ${iface} (HOME_NET=${local_cidr})"
    else
        ccdc_log warn "Suricata installed but service not yet active"
        systemctl restart suricata 2>/dev/null || true
    fi

    ccdc_undo_log "siem suricata -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem suricata --undo"
}

# ── zeek ──

_siem_zeek_etc() {
    # Find zeek config directory
    if [[ -d /opt/zeek/etc ]]; then
        echo "/opt/zeek/etc"
    elif [[ -d /etc/zeek ]]; then
        echo "/etc/zeek"
    elif [[ -d /usr/local/zeek/etc ]]; then
        echo "/usr/local/zeek/etc"
    else
        echo "/opt/zeek/etc"
    fi
}

_siem_zeek_bin() {
    if command -v zeekctl &>/dev/null; then
        echo "zeekctl"
    elif [[ -x /opt/zeek/bin/zeekctl ]]; then
        echo "/opt/zeek/bin/zeekctl"
    elif [[ -x /usr/local/zeek/bin/zeekctl ]]; then
        echo "/usr/local/zeek/bin/zeekctl"
    else
        echo ""
    fi
}

ccdc_siem_zeek() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem zeek)" || {
            ccdc_log error "No undo snapshot for siem zeek"
            return 1
        }
        local was_installed zeek_etc
        was_installed="$(cat "${snapshot_dir}/was_installed" 2>/dev/null)" || was_installed="no"
        zeek_etc="$(cat "${snapshot_dir}/zeek_etc" 2>/dev/null)" || zeek_etc="$(_siem_zeek_etc)"

        # Stop zeek
        local zeekctl
        zeekctl="$(_siem_zeek_bin)"
        [[ -n "$zeekctl" ]] && $zeekctl stop 2>/dev/null || true

        # Restore configs
        if [[ -f "${snapshot_dir}/node.cfg" ]]; then
            chattr -i "${snapshot_dir}/node.cfg" 2>/dev/null || true
            cp -a "${snapshot_dir}/node.cfg" "${zeek_etc}/node.cfg"
        fi
        if [[ -f "${snapshot_dir}/networks.cfg" ]]; then
            chattr -i "${snapshot_dir}/networks.cfg" 2>/dev/null || true
            cp -a "${snapshot_dir}/networks.cfg" "${zeek_etc}/networks.cfg"
        fi
        if [[ -f "${snapshot_dir}/local.zeek" ]]; then
            chattr -i "${snapshot_dir}/local.zeek" 2>/dev/null || true
            cp -a "${snapshot_dir}/local.zeek" "${zeek_etc}/site/local.zeek"
        fi

        # Remove zeek entries from ossec.conf
        if [[ -f /var/ossec/etc/ossec.conf ]]; then
            sed -i '/zeek.*conn\.log/,/<\/localfile>/d' /var/ossec/etc/ossec.conf 2>/dev/null || true
            sed -i '/zeek.*dns\.log/,/<\/localfile>/d' /var/ossec/etc/ossec.conf 2>/dev/null || true
            systemctl restart wazuh-agent 2>/dev/null || systemctl restart wazuh-manager 2>/dev/null || true
        fi

        if [[ "$was_installed" == "no" ]]; then
            ccdc_remove_pkg zeek 2>/dev/null || ccdc_remove_pkg zeek-lts 2>/dev/null || true
        fi

        ccdc_log success "siem zeek restored (undo)"
        ccdc_undo_log "siem zeek -- restored"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem zeek)"

    if command -v zeek &>/dev/null || command -v zeekctl &>/dev/null; then
        echo "yes" > "${snapshot_dir}/was_installed"
    else
        echo "no" > "${snapshot_dir}/was_installed"
    fi

    # Install zeek (not in default repos on most distros)
    local installed=false
    ccdc_install_pkg zeek 2>/dev/null && installed=true
    if [[ "$installed" == false ]]; then
        ccdc_install_pkg zeek-lts 2>/dev/null && installed=true
    fi
    if [[ "$installed" == false ]]; then
        # Try adding official Zeek repo
        case "${CCDC_PKG:-}" in
            apt)
                ccdc_log info "Adding Zeek OBS repository..."
                local codename
                codename="$(lsb_release -cs 2>/dev/null || echo 'focal')"
                ccdc_download "https://download.opensuse.org/repositories/security:/zeek/xUbuntu_$(lsb_release -rs 2>/dev/null || echo '22.04')/Release.key" /tmp/zeek.key 2>/dev/null && \
                    gpg --dearmor < /tmp/zeek.key > /usr/share/keyrings/zeek.gpg 2>/dev/null && \
                    echo "deb [signed-by=/usr/share/keyrings/zeek.gpg] https://download.opensuse.org/repositories/security:/zeek/xUbuntu_$(lsb_release -rs 2>/dev/null || echo '22.04')/ /" \
                        > /etc/apt/sources.list.d/zeek.list && \
                    apt-get update -qq 2>/dev/null && \
                    ccdc_install_pkg zeek && installed=true
                rm -f /tmp/zeek.key
                ;;
            dnf|yum)
                ccdc_log info "Adding Zeek OBS repository..."
                local os_ver
                os_ver="$(rpm -E %{rhel} 2>/dev/null || echo '8')"
                ccdc_download "https://download.opensuse.org/repositories/security:/zeek/CentOS_${os_ver}/security:zeek.repo" /etc/yum.repos.d/zeek.repo 2>/dev/null && \
                    ccdc_install_pkg zeek && installed=true
                if [[ "$installed" == false ]]; then
                    ccdc_install_pkg zeek-lts 2>/dev/null && installed=true
                fi
                ;;
        esac
    fi

    if [[ "$installed" == false ]]; then
        ccdc_log error "Failed to install zeek. You may need to add the Zeek repository manually."
        ccdc_undo_log "siem zeek -- install failed, snapshot at ${snapshot_dir}"
        return 0
    fi

    local zeek_etc zeek_logs iface local_cidr
    zeek_etc="$(_siem_zeek_etc)"
    echo "$zeek_etc" > "${snapshot_dir}/zeek_etc"
    iface="$(_siem_detect_iface)"
    local_cidr="$(ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4; exit}')"
    [[ -z "$local_cidr" ]] && local_cidr="10.0.0.0/8"

    # Find zeek log directory
    zeek_logs="/opt/zeek/logs"
    [[ -d /var/log/zeek ]] && zeek_logs="/var/log/zeek"

    mkdir -p "$zeek_etc"

    # Backup existing configs
    [[ -f "${zeek_etc}/node.cfg" ]] && ccdc_backup_file "${zeek_etc}/node.cfg" "$snapshot_dir"
    [[ -f "${zeek_etc}/networks.cfg" ]] && ccdc_backup_file "${zeek_etc}/networks.cfg" "$snapshot_dir"
    [[ -f "${zeek_etc}/site/local.zeek" ]] && ccdc_backup_file "${zeek_etc}/site/local.zeek" "$snapshot_dir"

    # Write node.cfg
    cat > "${zeek_etc}/node.cfg" <<EOF
[zeek]
type=standalone
host=localhost
interface=${iface}
EOF
    ccdc_log info "Wrote ${zeek_etc}/node.cfg (interface=${iface})"

    # Write networks.cfg
    cat > "${zeek_etc}/networks.cfg" <<EOF
${local_cidr}  Local network
EOF
    ccdc_log info "Wrote ${zeek_etc}/networks.cfg (${local_cidr})"

    # Ensure local.zeek loads standard scripts + JSON logging
    local site_dir="${zeek_etc}/site"
    mkdir -p "$site_dir"
    if [[ -f "${site_dir}/local.zeek" ]]; then
        # Append JSON logging if not already set
        if ! grep -q 'LogAscii::use_json' "${site_dir}/local.zeek" 2>/dev/null; then
            cat >> "${site_dir}/local.zeek" <<'EOF'

# ccdc-cli: enable JSON output for SIEM ingestion
redef LogAscii::use_json = T;
EOF
            ccdc_log info "Enabled JSON logging in local.zeek"
        fi
    else
        cat > "${site_dir}/local.zeek" <<'EOF'
# ccdc-cli zeek config
@load base/frameworks/logging
@load base/protocols/conn
@load base/protocols/dns
@load base/protocols/http
@load base/protocols/ssl
@load base/protocols/ssh
@load base/protocols/ftp
@load base/protocols/smtp
@load policy/misc/detect-traceroute
@load policy/frameworks/notice/community-id

# JSON output for SIEM ingestion
redef LogAscii::use_json = T;
EOF
        ccdc_log info "Wrote ${site_dir}/local.zeek with JSON logging"
    fi

    # Deploy zeek
    local zeekctl
    zeekctl="$(_siem_zeek_bin)"
    if [[ -n "$zeekctl" ]]; then
        $zeekctl install 2>/dev/null || true
        $zeekctl deploy 2>/dev/null || ccdc_log warn "zeekctl deploy returned non-zero"
        ccdc_log success "Zeek deployed on interface ${iface}"
    else
        ccdc_log warn "zeekctl not found; configs written but zeek not started"
    fi

    # Wazuh integration: forward zeek JSON logs
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        if ! grep -q 'zeek' /var/ossec/etc/ossec.conf 2>/dev/null; then
            sed -i "/<\/ossec_config>/i \\
  <localfile>\\
    <log_format>json<\\/log_format>\\
    <location>${zeek_logs}/current/conn.log<\\/location>\\
  <\\/localfile>\\
  <localfile>\\
    <log_format>json<\\/log_format>\\
    <location>${zeek_logs}/current/dns.log<\\/location>\\
  <\\/localfile>" /var/ossec/etc/ossec.conf
            ccdc_log info "Added zeek conn.log + dns.log to ossec.conf"
            systemctl restart wazuh-agent 2>/dev/null || systemctl restart wazuh-manager 2>/dev/null || true
        fi
    fi

    ccdc_undo_log "siem zeek -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem zeek --undo"
}

# ── wazuh-archives ──

ccdc_siem_wazuh_archives() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest siem wazuh-archives)" || {
            ccdc_log error "No undo snapshot for siem wazuh-archives"
            return 1
        }

        local wazuh_mode
        wazuh_mode="$(cat "${snapshot_dir}/wazuh_mode" 2>/dev/null)" || wazuh_mode="native"

        if [[ "$wazuh_mode" == "docker" ]]; then
            # Restore ossec.conf inside container
            local mgr_container
            mgr_container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep wazuh.manager | head -1)"
            if [[ -n "$mgr_container" && -f "${snapshot_dir}/ossec.conf" ]]; then
                docker cp "${snapshot_dir}/ossec.conf" "${mgr_container}:/var/ossec/etc/ossec.conf" 2>/dev/null || true
                docker restart "$mgr_container" 2>/dev/null || true
            fi
        else
            # Restore ossec.conf on host
            if [[ -f "${snapshot_dir}/ossec.conf" ]]; then
                chattr -i "${snapshot_dir}/ossec.conf" 2>/dev/null || true
                cp -a "${snapshot_dir}/ossec.conf" /var/ossec/etc/ossec.conf
            fi
            if systemctl is-active wazuh-manager &>/dev/null; then
                systemctl restart wazuh-manager 2>/dev/null || true
            fi
            # Restore filebeat.yml
            if [[ -f "${snapshot_dir}/filebeat.yml" ]]; then
                chattr -i "${snapshot_dir}/filebeat.yml" 2>/dev/null || true
                cp -a "${snapshot_dir}/filebeat.yml" /etc/filebeat/filebeat.yml
                systemctl restart filebeat 2>/dev/null || true
            fi
        fi

        # Remove rotation/guard files (same for both modes)
        rm -f /etc/logrotate.d/wazuh-archives
        rm -f /etc/cron.hourly/wazuh-rotate
        rm -f /etc/cron.d/wazuh-disk-guard
        rm -f /etc/cron.hourly/wazuh-archives-cleanup

        ccdc_log success "siem wazuh-archives restored (undo)"
        ccdc_undo_log "siem wazuh-archives -- restored"
        return 0
    fi

    # Detect install method: native (ossec.conf on host) or docker compose
    local wazuh_mode="none"
    if [[ -f /var/ossec/etc/ossec.conf ]]; then
        wazuh_mode="native"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q wazuh.manager; then
        wazuh_mode="docker"
    fi

    if [[ "$wazuh_mode" == "none" ]]; then
        ccdc_log error "wazuh-manager not found (no ossec.conf, no docker container). Install wazuh-server first."
        return 1
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create siem wazuh-archives)"
    echo "$wazuh_mode" > "${snapshot_dir}/wazuh_mode"

    if [[ "$wazuh_mode" == "docker" ]]; then
        # Docker compose path: edit ossec.conf inside the container
        local mgr_container
        mgr_container="$(docker ps --format '{{.Names}}' | grep wazuh.manager | head -1)"

        # Backup ossec.conf from container
        docker cp "${mgr_container}:/var/ossec/etc/ossec.conf" "${snapshot_dir}/ossec.conf" 2>/dev/null || true

        # Enable logall_json inside the container
        docker exec "$mgr_container" bash -c '
            if grep -q "<logall_json>" /var/ossec/etc/ossec.conf; then
                sed -i "s|<logall_json>no</logall_json>|<logall_json>yes</logall_json>|" /var/ossec/etc/ossec.conf
            else
                sed -i "/<global>/a\\    <logall_json>yes<\\/logall_json>" /var/ossec/etc/ossec.conf
            fi
        ' 2>/dev/null
        ccdc_log info "Enabled logall_json in container ossec.conf"

        # Restart manager container to apply
        docker restart "$mgr_container" 2>/dev/null || true
        ccdc_log info "Restarted wazuh-manager container"

        # Host-side cron jobs still apply (guard disk from container log volume)
        # 2. Logrotate config
        cat > /etc/logrotate.d/wazuh-archives <<'EOF'
/var/lib/docker/volumes/*wazuh*/_data/logs/archives/archives.json {
    hourly
    rotate 6
    compress
    delaycompress
    copytruncate
    maxsize 500M
    missingok
    notifempty
}
EOF
        ccdc_log info "Wrote /etc/logrotate.d/wazuh-archives (docker volume path)"

        # 3. Hourly logrotate trigger
        cat > /etc/cron.hourly/wazuh-rotate <<'EOF'
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.d/wazuh-archives
EOF
        chmod +x /etc/cron.hourly/wazuh-rotate
        ccdc_log info "Wrote /etc/cron.hourly/wazuh-rotate"

        # 4. Disk guard cron
        cat > /etc/cron.d/wazuh-disk-guard <<'EOF'
*/5 * * * * root pct=$(df /var --output=pcent | tail -1 | tr -d ' %'); [ "$pct" -gt 85 ] && find /var/lib/docker/volumes/ -path '*archives*.gz' -print0 2>/dev/null | xargs -0 ls -1t 2>/dev/null | tail -3 | xargs -r rm -f
EOF
        ccdc_log info "Wrote /etc/cron.d/wazuh-disk-guard"

        ccdc_undo_log "siem wazuh-archives -- snapshot at ${snapshot_dir}"
        ccdc_log success "Done (docker mode). Undo: ccdc siem wazuh-archives --undo"
        return 0
    fi

    # --- Native install path ---

    # Backup ossec.conf
    ccdc_backup_file /var/ossec/etc/ossec.conf "$snapshot_dir"

    # Backup filebeat.yml if present
    [[ -f /etc/filebeat/filebeat.yml ]] && ccdc_backup_file /etc/filebeat/filebeat.yml "$snapshot_dir"

    # 1. Enable logall_json in ossec.conf
    if grep -q '<logall_json>' /var/ossec/etc/ossec.conf 2>/dev/null; then
        sed -i 's|<logall_json>no</logall_json>|<logall_json>yes</logall_json>|' /var/ossec/etc/ossec.conf
    else
        # Insert inside <global> block
        sed -i '/<global>/a \    <logall_json>yes<\/logall_json>' /var/ossec/etc/ossec.conf
    fi
    ccdc_log info "Enabled logall_json in ossec.conf"

    # 2. Logrotate config
    cat > /etc/logrotate.d/wazuh-archives <<'EOF'
/var/ossec/logs/archives/archives.json {
    hourly
    rotate 6
    compress
    delaycompress
    copytruncate
    maxsize 500M
    missingok
    notifempty
}
EOF
    ccdc_log info "Wrote /etc/logrotate.d/wazuh-archives"

    # 3. Hourly logrotate trigger
    cat > /etc/cron.hourly/wazuh-rotate <<'EOF'
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.d/wazuh-archives
EOF
    chmod +x /etc/cron.hourly/wazuh-rotate
    ccdc_log info "Wrote /etc/cron.hourly/wazuh-rotate"

    # 4. Disk guard cron
    cat > /etc/cron.d/wazuh-disk-guard <<'EOF'
*/5 * * * * root pct=$(df /var --output=pcent | tail -1 | tr -d ' %'); [ "$pct" -gt 85 ] && ls -1t /var/ossec/logs/archives/*.gz 2>/dev/null | tail -3 | xargs -r rm -f
EOF
    ccdc_log info "Wrote /etc/cron.d/wazuh-disk-guard"

    # 5. Restart wazuh-manager
    systemctl restart wazuh-manager 2>/dev/null || true
    ccdc_log info "Restarted wazuh-manager service"

    # 6. Enable filebeat archives input
    if [[ -f /etc/filebeat/filebeat.yml ]]; then
        if grep -q 'archives' /etc/filebeat/filebeat.yml 2>/dev/null; then
            sed -i '/archives:/,/enabled:/{s/enabled: false/enabled: true/}' /etc/filebeat/filebeat.yml
        fi
        systemctl restart filebeat 2>/dev/null || true
        ccdc_log info "Enabled archives input in filebeat.yml"
    else
        ccdc_log info "filebeat.yml not found; skipping filebeat archives config"
    fi

    # 7. Index cleanup cron
    cat > /etc/cron.hourly/wazuh-archives-cleanup <<'EOF'
#!/bin/sh
# Delete wazuh-archives indices older than 6 hours
sixh_ago=$(date -u -d '6 hours ago' +%Y.%m.%d 2>/dev/null) || exit 0
curl -s -k -u admin:SecretPassword -XDELETE "https://localhost:9200/wazuh-archives-${sixh_ago}*" 2>/dev/null || true
EOF
    chmod +x /etc/cron.hourly/wazuh-archives-cleanup
    ccdc_log info "Wrote /etc/cron.hourly/wazuh-archives-cleanup"

    # Verify
    if [[ -d /var/ossec/logs/archives ]]; then
        ccdc_log success "Archives directory exists at /var/ossec/logs/archives/"
    fi
    if logrotate -d /etc/logrotate.d/wazuh-archives &>/dev/null; then
        ccdc_log success "Logrotate config parses OK"
    fi

    ccdc_undo_log "siem wazuh-archives -- snapshot at ${snapshot_dir}"
    ccdc_log success "Done. Undo: ccdc siem wazuh-archives --undo"
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
        suricata)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem suricata"; echo "Install Suricata IDS"; return 0; }
            ccdc_siem_suricata "$@"
            ;;
        zeek)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem zeek"; echo "Install Zeek network monitor (Linux only)"; return 0; }
            ccdc_siem_zeek "$@"
            ;;
        docker)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem docker"; echo "Install Docker engine"; return 0; }
            ccdc_siem_docker "$@"
            ;;
        wazuh-archives)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc siem wazuh-archives"; echo "Enable full forensics logging on Wazuh server"; return 0; }
            ccdc_siem_wazuh_archives "$@"
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
