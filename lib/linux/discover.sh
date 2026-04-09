#!/usr/bin/env bash
# ccdc-cli: discovery module
# Depends on: common.sh, detect.sh, config.sh

# ── Usage ──

ccdc_discover_usage() {
    echo -e "${CCDC_BOLD}ccdc discover${CCDC_NC} — System discovery and enumeration"
    echo ""
    echo "Commands:"
    echo "  network (net)        Show network interfaces, routes, DNS"
    echo "  ports                Show listening ports and connections"
    echo "  users                List users, groups, sudo/wheel membership, sudoers"
    echo "  processes (ps)       Show running processes"
    echo "  cron                 List cron jobs, scheduled tasks, profile scripts"
    echo "  services (svc)       List running and enabled services"
    echo "  firewall (fw)        Dump current firewall rules"
    echo "  integrity            Check package integrity (debsums/rpm -Va)"
    echo "  all                  Run all discovery commands"
    echo ""
    echo "Options:"
    echo "  --help"
    echo "  -h                   Show help"
    echo ""
    echo "All output is saved to ${CCDC_BACKUP_DIR:-/ccdc-backups}/discovery/"
    echo ""
    echo "Examples:"
    echo "  ccdc disc net                   Show network config"
    echo "  ccdc disc ports                 Show listening ports"
    echo "  ccdc disc users                 Enumerate users and groups"
    echo "  ccdc disc all                   Run full discovery"
}

# ── Internal Helpers ──

_discover_outdir() {
    local outdir="${CCDC_BACKUP_DIR}/discovery"
    mkdir -p "$outdir"
    echo "$outdir"
}

_discover_save() {
    local outfile="$1"
    local label="$2"
    tee "$outfile"
    ccdc_log success "Saved to ${outfile}"
}

# ── Network ──

ccdc_discover_network() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover network"; echo "Show network interfaces, routes, and DNS"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/network.txt"

    ccdc_log info "Discovering network configuration..."
    {
        echo "=== IP Addresses ==="
        ip a 2>/dev/null || ifconfig 2>/dev/null || echo "(no ip/ifconfig found)"
        echo ""
        echo "=== Routes ==="
        ip r 2>/dev/null || route -n 2>/dev/null || echo "(no ip/route found)"
        echo ""
        echo "=== IPv6 Routes ==="
        ip -6 r 2>/dev/null || true
        echo ""
        echo "=== DNS Config ==="
        cat /etc/resolv.conf 2>/dev/null || echo "(no resolv.conf)"
        echo ""
        echo "=== Hostname ==="
        hostname 2>/dev/null || true
        hostname -f 2>/dev/null || true
    } | _discover_save "$outfile" "network"
}

# ── Ports ──

ccdc_discover_ports() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover ports"; echo "Show listening ports and active connections"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/ports.txt"

    ccdc_log info "Discovering listening ports..."
    {
        echo "=== Listening Ports (ss) ==="
        ss -lntup 2>/dev/null || netstat -tlnp 2>/dev/null || echo "(no ss/netstat found)"
        echo ""
        echo "=== All Connections ==="
        ss -autpn 2>/dev/null || netstat -anp 2>/dev/null || echo "(no ss/netstat found)"
    } | _discover_save "$outfile" "ports"
}

# ── Users ──

ccdc_discover_users() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover users"; echo "List users, groups, sudo/wheel, sudoers"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/users.txt"

    ccdc_log info "Discovering users and groups..."
    {
        echo "=== Users (/etc/passwd) ==="
        while IFS=: read -r username _ uid gid _ homedir shell; do
            local groups
            groups="$(id -Gn "$username" 2>/dev/null | tr ' ' ',')" || groups="?"
            echo "  ${username} (uid=${uid}) home=${homedir} shell=${shell} groups=${groups}"
        done < /etc/passwd
        echo ""

        echo "=== Sudo/Wheel Group Members ==="
        getent group sudo 2>/dev/null || true
        getent group wheel 2>/dev/null || true
        echo ""

        echo "=== /etc/sudoers ==="
        cat /etc/sudoers 2>/dev/null || echo "(cannot read /etc/sudoers)"
        echo ""

        echo "=== /etc/sudoers.d/ ==="
        if [[ -d /etc/sudoers.d ]]; then
            for f in /etc/sudoers.d/*; do
                [[ -f "$f" ]] || continue
                echo "--- ${f} ---"
                cat "$f" 2>/dev/null || echo "(cannot read)"
            done
        else
            echo "(no sudoers.d directory)"
        fi
        echo ""

        echo "=== Users With Login Shells ==="
        grep -v -E '(/nologin|/false|/sync|/halt|/shutdown)$' /etc/passwd 2>/dev/null || true
        echo ""

        echo "=== Locked Users ==="
        while IFS=: read -r username _; do
            local status
            status="$(passwd -S "$username" 2>/dev/null | awk '{print $2}')" || continue
            case "$status" in
                L|LK) echo "  LOCKED: ${username}" ;;
            esac
        done < /etc/passwd
    } | _discover_save "$outfile" "users"
}

# ── Processes ─��

ccdc_discover_processes() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover processes"; echo "Show running processes"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/processes.txt"

    ccdc_log info "Discovering running processes..."
    {
        echo "=== Process Tree ==="
        ps -eaf --forest 2>/dev/null || ps -eaf 2>/dev/null || ps aux 2>/dev/null || echo "(no ps found)"
    } | _discover_save "$outfile" "processes"
}

# ── Cron ──

ccdc_discover_cron() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover cron"; echo "List cron jobs, profile scripts, bashrc entries"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/cron.txt"

    ccdc_log info "Discovering cron jobs and scheduled tasks..."
    {
        echo "=== System Crontab (/etc/crontab) ==="
        cat /etc/crontab 2>/dev/null || echo "(no /etc/crontab)"
        echo ""

        echo "=== /etc/cron.d/ ==="
        for f in /etc/cron.d/*; do
            [[ -f "$f" ]] || continue
            echo "--- ${f} ---"
            cat "$f" 2>/dev/null || true
        done
        echo ""

        echo "=== /etc/cron.daily/ ==="
        ls -la /etc/cron.daily/ 2>/dev/null || true
        echo ""
        echo "=== /etc/cron.hourly/ ==="
        ls -la /etc/cron.hourly/ 2>/dev/null || true
        echo ""
        echo "=== /etc/cron.weekly/ ==="
        ls -la /etc/cron.weekly/ 2>/dev/null || true
        echo ""
        echo "=== /etc/cron.monthly/ ==="
        ls -la /etc/cron.monthly/ 2>/dev/null || true
        echo ""

        echo "=== User Crontabs ==="
        while IFS=: read -r username _; do
            local crontab_output
            crontab_output="$(crontab -l -u "$username" 2>/dev/null)" || continue
            if [[ -n "$crontab_output" ]]; then
                echo "--- ${username} ---"
                echo "$crontab_output"
                echo ""
            fi
        done < /etc/passwd

        echo "=== /etc/profile.d/ ==="
        for f in /etc/profile.d/*; do
            [[ -f "$f" ]] || continue
            echo "--- ${f} ---"
            cat "$f" 2>/dev/null || true
        done
        echo ""

        echo "=== Suspicious .bashrc/.profile entries ==="
        local suspicious_patterns='(/dev/tcp|nc -e|nc -c|bash -i|ncat|socat|python.*socket|perl.*socket|ruby.*socket|wget.*\|.*sh|curl.*\|.*sh)'
        for homedir in /root /home/*; do
            for rcfile in .bashrc .profile .bash_profile .bash_login; do
                local filepath="${homedir}/${rcfile}"
                [[ -f "$filepath" ]] || continue
                local matches
                matches="$(grep -nE "$suspicious_patterns" "$filepath" 2>/dev/null)" || true
                if [[ -n "$matches" ]]; then
                    echo "  SUSPICIOUS: ${filepath}"
                    echo "$matches"
                fi
            done
        done
    } | _discover_save "$outfile" "cron"
}

# ── Services ──

ccdc_discover_services() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover services"; echo "List running and enabled services"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/services.txt"

    ccdc_log info "Discovering services..."
    {
        echo "=== Running Services ==="
        systemctl list-units --type=service --state=running --no-pager 2>/dev/null || \
            service --status-all 2>/dev/null || echo "(no systemctl/service found)"
        echo ""

        echo "=== Enabled Services ==="
        systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null || true
        echo ""

        echo "=== Failed Services ==="
        systemctl list-units --type=service --state=failed --no-pager 2>/dev/null || true
    } | _discover_save "$outfile" "services"
}

# ── Firewall ──

ccdc_discover_firewall() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover firewall"; echo "Dump current firewall rules"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/firewall.txt"

    ccdc_log info "Discovering firewall rules (backend: ${CCDC_FW_BACKEND:-unknown})..."
    {
        echo "=== Detected Backend: ${CCDC_FW_BACKEND:-unknown} ==="
        echo "=== Available Backends: ${CCDC_FW_AVAILABLE[*]:-none} ==="
        echo ""

        # Dump all available backends
        if command -v iptables &>/dev/null; then
            echo "=== iptables (IPv4) ==="
            iptables -L -n -v --line-numbers 2>/dev/null || echo "(iptables not accessible)"
            echo ""
            echo "=== iptables (IPv6) ==="
            ip6tables -L -n -v --line-numbers 2>/dev/null || echo "(ip6tables not accessible)"
            echo ""
        fi

        if command -v nft &>/dev/null; then
            echo "=== nftables ==="
            nft list ruleset 2>/dev/null || echo "(nft not accessible)"
            echo ""
        fi

        if command -v ufw &>/dev/null; then
            echo "=== UFW ==="
            ufw status verbose 2>/dev/null || echo "(ufw not accessible)"
            echo ""
        fi

        if command -v firewall-cmd &>/dev/null; then
            echo "=== firewalld ==="
            firewall-cmd --state 2>/dev/null || true
            firewall-cmd --list-all-zones 2>/dev/null || echo "(firewalld not accessible)"
            echo ""
        fi
    } | _discover_save "$outfile" "firewall"
}

# ── Integrity ──

ccdc_discover_integrity() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover integrity"; echo "Check package integrity (debsums or rpm -Va)"; return 0; }

    local outdir
    outdir="$(_discover_outdir)"
    local outfile="${outdir}/integrity.txt"

    ccdc_log info "Checking package integrity (this may take a while)..."
    {
        case "${CCDC_OS_FAMILY}" in
            debian)
                if ! command -v debsums &>/dev/null; then
                    ccdc_log info "Installing debsums..."
                    ccdc_install_pkg debsums 2>/dev/null || true
                fi
                if command -v debsums &>/dev/null; then
                    echo "=== debsums (modified files) ==="
                    debsums -s 2>/dev/null || debsums -c 2>/dev/null || echo "(debsums failed)"
                else
                    echo "(debsums not available)"
                fi
                ;;
            rhel)
                echo "=== rpm -Va (modified files) ==="
                rpm -Va 2>/dev/null || echo "(rpm verification failed)"
                ;;
            *)
                echo "(integrity check not supported for ${CCDC_OS_FAMILY})"
                ;;
        esac
    } | _discover_save "$outfile" "integrity"
}

# ── All ──

ccdc_discover_all() {
    [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc discover all"; echo "Run all discovery commands"; return 0; }

    ccdc_log info "Running full system discovery..."
    echo ""

    local failed=0

    ccdc_discover_network || ((failed++))
    echo ""
    ccdc_discover_ports || ((failed++))
    echo ""
    ccdc_discover_users || ((failed++))
    echo ""
    ccdc_discover_processes || ((failed++))
    echo ""
    ccdc_discover_cron || ((failed++))
    echo ""
    ccdc_discover_services || ((failed++))
    echo ""
    ccdc_discover_firewall || ((failed++))
    echo ""
    ccdc_discover_integrity || ((failed++))
    echo ""

    local outdir="${CCDC_BACKUP_DIR}/discovery"
    ccdc_log info "=== Discovery Summary ==="
    ccdc_log info "Output directory: ${outdir}"
    local count
    count="$(ls -1 "${outdir}"/*.txt 2>/dev/null | wc -l)"
    ccdc_log info "Files created: ${count}"
    if [[ "$failed" -gt 0 ]]; then
        ccdc_log warn "${failed} discovery commands had errors"
    else
        ccdc_log success "All discovery commands completed successfully"
    fi
}

# ── Handler (main router) ──

ccdc_discover_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_discover_usage
        return 0
    fi

    case "$cmd" in
        network|net)
            ccdc_discover_network "$@"
            ;;
        ports)
            ccdc_discover_ports "$@"
            ;;
        users)
            ccdc_discover_users "$@"
            ;;
        processes|ps)
            ccdc_discover_processes "$@"
            ;;
        cron)
            ccdc_discover_cron "$@"
            ;;
        services|svc)
            ccdc_discover_services "$@"
            ;;
        firewall|fw)
            ccdc_discover_firewall "$@"
            ;;
        integrity)
            ccdc_discover_integrity "$@"
            ;;
        all)
            ccdc_discover_all "$@"
            ;;
        "")
            ccdc_discover_usage
            ;;
        *)
            ccdc_log error "Unknown discover command: ${cmd}"
            ccdc_discover_usage
            return 1
            ;;
    esac
}
