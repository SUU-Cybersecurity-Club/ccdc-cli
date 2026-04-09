#!/usr/bin/env bash
# ccdc-cli: firewall module
# Depends on: common.sh, detect.sh, config.sh, undo.sh
# Supports 4 backends: iptables, nft, ufw, firewalld

# ── Usage ──

ccdc_firewall_usage() {
    echo -e "${CCDC_BOLD}ccdc firewall${CCDC_NC} — Firewall management"
    echo ""
    echo "Commands:"
    echo "  on                   Enable firewall, disable competing backends"
    echo "  allow-in <port> [p]  Allow inbound port (default: tcp)"
    echo "  block-in <port> [p]  Block inbound port"
    echo "  allow-out <port> [p] Allow outbound port"
    echo "  block-out <port> [p] Block outbound port"
    echo "  drop-all-in          Default deny all inbound"
    echo "  drop-all-out         Default deny all outbound"
    echo "  allow-only-in <p,p>  Drop all except listed ports (in+out)"
    echo "  block-ip <ip>        Block all traffic from IP"
    echo "  status               Show current firewall rules"
    echo "  save                 Persist rules across reboot"
    echo "  allow-internet       Open outbound 80,443,53 for downloads"
    echo "  block-internet       Close outbound 80,443,53"
    echo ""
    echo "Options:"
    echo "  --activate <sec>     Auto-revert rules after N seconds unless confirmed"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Backend: ${CCDC_FW_BACKEND:-not detected}"
    echo ""
    echo "Examples:"
    echo "  ccdc fw on                          Enable firewall"
    echo "  ccdc fw allow-only-in 22,80,443     Lock down to scored ports"
    echo "  ccdc fw allow-only-in               Use scored_ports_tcp from config"
    echo "  ccdc fw allow-in 8080               Open port 8080/tcp inbound"
    echo "  ccdc fw block-ip 10.0.0.99          Block attacker IP"
    echo "  ccdc fw status                      Show rules"
    echo "  ccdc fw save                        Persist rules"
    echo "  ccdc fw allow-internet              Temp open outbound for downloads"
    echo "  ccdc fw allow-only-in --activate 30 Apply rules, auto-revert in 30s"
}

# ══════════════════════════════════════════════
# Internal Helpers
# ══════════════════════════════════════════════

# Parse --activate <seconds> from args, sets _FW_ACTIVATE_TIMEOUT
_fw_parse_activate() {
    _FW_ACTIVATE_TIMEOUT=""
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "--activate" && -n "${args[i+1]:-}" ]]; then
            _FW_ACTIVATE_TIMEOUT="${args[i+1]}"
            return 0
        fi
    done
    return 1
}

# Save current rules to snapshot dir (all backends)
_fw_save_current_rules() {
    local dir="$1"
    case "$CCDC_FW_BACKEND" in
        iptables)
            iptables-save > "${dir}/iptables.rules" 2>/dev/null || true
            ip6tables-save > "${dir}/ip6tables.rules" 2>/dev/null || true
            ;;
        nft)
            nft list ruleset > "${dir}/nft.rules" 2>/dev/null || true
            ;;
        ufw)
            cp /etc/ufw/user.rules "${dir}/user.rules" 2>/dev/null || true
            cp /etc/ufw/user6.rules "${dir}/user6.rules" 2>/dev/null || true
            cp /etc/ufw/before.rules "${dir}/before.rules" 2>/dev/null || true
            cp /etc/ufw/after.rules "${dir}/after.rules" 2>/dev/null || true
            ufw status numbered > "${dir}/ufw.status" 2>/dev/null || true
            ;;
        firewalld)
            firewall-cmd --list-all-zones > "${dir}/firewalld.zones" 2>/dev/null || true
            cp -r /etc/firewalld/zones/ "${dir}/zones/" 2>/dev/null || true
            firewall-cmd --direct --get-all-rules > "${dir}/firewalld.direct" 2>/dev/null || true
            ;;
    esac
}

# Restore rules from snapshot dir
_fw_restore_from_snapshot() {
    local dir="$1"
    ccdc_log info "Restoring firewall rules from ${dir}..."
    case "$CCDC_FW_BACKEND" in
        iptables)
            [[ -f "${dir}/iptables.rules" ]] && iptables-restore < "${dir}/iptables.rules"
            [[ -f "${dir}/ip6tables.rules" ]] && ip6tables-restore < "${dir}/ip6tables.rules"
            ccdc_log success "iptables rules restored"
            ;;
        nft)
            nft flush ruleset 2>/dev/null || true
            [[ -f "${dir}/nft.rules" ]] && nft -f "${dir}/nft.rules"
            ccdc_log success "nft rules restored"
            ;;
        ufw)
            [[ -f "${dir}/user.rules" ]] && cp "${dir}/user.rules" /etc/ufw/user.rules
            [[ -f "${dir}/user6.rules" ]] && cp "${dir}/user6.rules" /etc/ufw/user6.rules
            [[ -f "${dir}/before.rules" ]] && cp "${dir}/before.rules" /etc/ufw/before.rules
            [[ -f "${dir}/after.rules" ]] && cp "${dir}/after.rules" /etc/ufw/after.rules
            ufw reload 2>/dev/null || true
            ccdc_log success "ufw rules restored"
            ;;
        firewalld)
            if [[ -d "${dir}/zones/" ]]; then
                cp -f "${dir}/zones/"*.xml /etc/firewalld/zones/ 2>/dev/null || true
            fi
            firewall-cmd --reload 2>/dev/null || true
            ccdc_log success "firewalld rules restored"
            ;;
    esac
}

# Undo handler for firewall commands
_fw_undo() {
    local cmd="$1"
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_latest firewall "$cmd")" || {
        ccdc_log error "No undo snapshot found for firewall ${cmd}"
        return 1
    }
    _fw_restore_from_snapshot "$snapshot_dir"
}

# Auto-revert timer (--activate <seconds>)
_fw_activate_timer() {
    local snapshot_dir="$1"
    local timeout="$2"

    ccdc_log warn "Rules will auto-revert in ${timeout}s unless you confirm"
    (
        sleep "$timeout"
        _fw_restore_from_snapshot "$snapshot_dir"
        ccdc_log warn "Firewall rules auto-reverted (timeout reached)"
    ) &
    local revert_pid=$!

    if ccdc_confirm "Keep the new firewall rules?"; then
        kill $revert_pid 2>/dev/null || true
        wait $revert_pid 2>/dev/null || true
        ccdc_log success "Rules confirmed and kept"
    else
        # Let the background job do the revert
        wait $revert_pid 2>/dev/null || true
        ccdc_log info "Rules reverted"
    fi
}

# ══════════════════════════════════════════════
# Backend Dispatcher
# ══════════════════════════════════════════════

_fw_dispatch() {
    local action="$1"
    shift
    case "$CCDC_FW_BACKEND" in
        iptables)  "_fw_iptables_${action}" "$@" ;;
        nft)       "_fw_nft_${action}" "$@" ;;
        ufw)       "_fw_ufw_${action}" "$@" ;;
        firewalld) "_fw_firewalld_${action}" "$@" ;;
        *)
            ccdc_log error "No firewall backend detected (CCDC_FW_BACKEND=${CCDC_FW_BACKEND:-unset})"
            ccdc_log info "Run: ccdc config init"
            return 1
            ;;
    esac
}

# ══════════════════════════════════════════════
# iptables Backend
# ══════════════════════════════════════════════

_fw_iptables_on() {
    ccdc_log info "Enabling iptables..."
    # Disable competing backends
    for svc in firewalld ufw nftables; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    done
    # Foundation rules
    iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    ccdc_log success "iptables enabled with foundation rules"
}

_fw_iptables_allow_in() {
    local port="$1" proto="${2:-tcp}"
    iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
    ccdc_log success "iptables: allowed inbound ${port}/${proto}"
}

_fw_iptables_block_in() {
    local port="$1" proto="${2:-tcp}"
    iptables -A INPUT -p "$proto" --dport "$port" -j DROP
    ccdc_log success "iptables: blocked inbound ${port}/${proto}"
}

_fw_iptables_allow_out() {
    local port="$1" proto="${2:-tcp}"
    iptables -A OUTPUT -p "$proto" --dport "$port" -j ACCEPT
    ccdc_log success "iptables: allowed outbound ${port}/${proto}"
}

_fw_iptables_block_out() {
    local port="$1" proto="${2:-tcp}"
    iptables -A OUTPUT -p "$proto" --dport "$port" -j DROP
    ccdc_log success "iptables: blocked outbound ${port}/${proto}"
}

_fw_iptables_drop_all_in() {
    # Ensure foundation rules exist before setting DROP
    iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -I INPUT -i lo -j ACCEPT
    iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -P INPUT DROP
    ccdc_log success "iptables: default INPUT policy set to DROP"
}

_fw_iptables_drop_all_out() {
    iptables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || iptables -I OUTPUT -o lo -j ACCEPT
    iptables -C OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I OUTPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -P OUTPUT DROP
    ccdc_log success "iptables: default OUTPUT policy set to DROP"
}

_fw_iptables_allow_only_in() {
    local ports="$1"
    # Flush all rules
    iptables -F
    iptables -X 2>/dev/null || true
    # Foundation: loopback + established
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # Allow inbound on scored ports
    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="$(echo "$port" | tr -d ' ')"
        [[ -z "$port" ]] && continue
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        ccdc_log info "iptables: allowed inbound ${port}/tcp"
    done
    # UDP scored ports
    if [[ -n "${CCDC_SCORED_UDP:-}" ]]; then
        IFS=',' read -ra udp_list <<< "$CCDC_SCORED_UDP"
        for port in "${udp_list[@]}"; do
            port="$(echo "$port" | tr -d ' ')"
            [[ -z "$port" ]] && continue
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
            ccdc_log info "iptables: allowed inbound ${port}/udp"
        done
    fi
    # Default DROP on both
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    ccdc_log success "iptables: allow-only-in applied (${ports}), all other traffic dropped"
}

_fw_iptables_block_ip() {
    local ip="$1"
    iptables -I INPUT -s "$ip" -j DROP
    iptables -I OUTPUT -d "$ip" -j DROP
    ccdc_log success "iptables: blocked all traffic from/to ${ip}"
}

_fw_iptables_status() {
    echo "=== iptables IPv4 ==="
    iptables -L -n -v --line-numbers 2>/dev/null || echo "(iptables not accessible)"
    echo ""
    echo "=== iptables IPv6 ==="
    ip6tables -L -n -v --line-numbers 2>/dev/null || echo "(ip6tables not accessible)"
}

_fw_iptables_save() {
    case "${CCDC_OS_FAMILY}" in
        debian)
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
            # Install iptables-persistent if available
            if ! dpkg -l iptables-persistent &>/dev/null; then
                ccdc_log info "Installing iptables-persistent..."
                DEBIAN_FRONTEND=noninteractive ccdc_install_pkg iptables-persistent 2>/dev/null || true
            fi
            ccdc_log success "iptables rules saved to /etc/iptables/rules.v4"
            ;;
        rhel)
            iptables-save > /etc/sysconfig/iptables
            ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null || true
            ccdc_log success "iptables rules saved to /etc/sysconfig/iptables"
            ;;
        *)
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
            ccdc_log success "iptables rules saved to /etc/iptables/rules.v4"
            ;;
    esac
}

_fw_iptables_allow_internet() {
    iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    ccdc_log success "iptables: outbound 80,443,53 opened"
}

_fw_iptables_block_internet() {
    iptables -D OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    ccdc_log success "iptables: outbound 80,443,53 closed"
}

# ══════════════════════════════════════════════
# nftables Backend
# ══════════════════════════════════════════════

_fw_nft_ensure_table() {
    nft list table inet filter &>/dev/null || nft add table inet filter
    nft list chain inet filter input &>/dev/null || \
        nft 'add chain inet filter input { type filter hook input priority 0; policy accept; }'
    nft list chain inet filter output &>/dev/null || \
        nft 'add chain inet filter output { type filter hook output priority 0; policy accept; }'
}

_fw_nft_on() {
    ccdc_log info "Enabling nftables..."
    for svc in firewalld ufw; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    done
    systemctl enable --now nftables 2>/dev/null || true
    _fw_nft_ensure_table
    # Foundation rules
    nft add rule inet filter input iif lo accept 2>/dev/null || true
    nft add rule inet filter output oif lo accept 2>/dev/null || true
    nft add rule inet filter input ct state established,related accept 2>/dev/null || true
    nft add rule inet filter output ct state established,related accept 2>/dev/null || true
    ccdc_log success "nftables enabled with foundation rules"
}

_fw_nft_allow_in() {
    local port="$1" proto="${2:-tcp}"
    _fw_nft_ensure_table
    nft add rule inet filter input "$proto" dport "$port" accept
    ccdc_log success "nft: allowed inbound ${port}/${proto}"
}

_fw_nft_block_in() {
    local port="$1" proto="${2:-tcp}"
    _fw_nft_ensure_table
    nft add rule inet filter input "$proto" dport "$port" drop
    ccdc_log success "nft: blocked inbound ${port}/${proto}"
}

_fw_nft_allow_out() {
    local port="$1" proto="${2:-tcp}"
    _fw_nft_ensure_table
    nft add rule inet filter output "$proto" dport "$port" accept
    ccdc_log success "nft: allowed outbound ${port}/${proto}"
}

_fw_nft_block_out() {
    local port="$1" proto="${2:-tcp}"
    _fw_nft_ensure_table
    nft add rule inet filter output "$proto" dport "$port" drop
    ccdc_log success "nft: blocked outbound ${port}/${proto}"
}

_fw_nft_drop_all_in() {
    _fw_nft_ensure_table
    # Re-create input chain with drop policy
    nft flush chain inet filter input 2>/dev/null || true
    nft 'add chain inet filter input { type filter hook input priority 0; policy drop; }'
    nft add rule inet filter input iif lo accept
    nft add rule inet filter input ct state established,related accept
    ccdc_log success "nft: default input policy set to drop"
}

_fw_nft_drop_all_out() {
    _fw_nft_ensure_table
    nft flush chain inet filter output 2>/dev/null || true
    nft 'add chain inet filter output { type filter hook output priority 0; policy drop; }'
    nft add rule inet filter output oif lo accept
    nft add rule inet filter output ct state established,related accept
    ccdc_log success "nft: default output policy set to drop"
}

_fw_nft_allow_only_in() {
    local ports="$1"
    # Flush and rebuild
    nft flush ruleset 2>/dev/null || true
    nft add table inet filter
    nft 'add chain inet filter input { type filter hook input priority 0; policy drop; }'
    nft 'add chain inet filter output { type filter hook output priority 0; policy drop; }'
    # Foundation
    nft add rule inet filter input iif lo accept
    nft add rule inet filter output oif lo accept
    nft add rule inet filter input ct state established,related accept
    nft add rule inet filter output ct state established,related accept
    # Scored TCP ports
    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="$(echo "$port" | tr -d ' ')"
        [[ -z "$port" ]] && continue
        nft add rule inet filter input tcp dport "$port" accept
        ccdc_log info "nft: allowed inbound ${port}/tcp"
    done
    # Scored UDP ports
    if [[ -n "${CCDC_SCORED_UDP:-}" ]]; then
        IFS=',' read -ra udp_list <<< "$CCDC_SCORED_UDP"
        for port in "${udp_list[@]}"; do
            port="$(echo "$port" | tr -d ' ')"
            [[ -z "$port" ]] && continue
            nft add rule inet filter input udp dport "$port" accept
            ccdc_log info "nft: allowed inbound ${port}/udp"
        done
    fi
    ccdc_log success "nft: allow-only-in applied (${ports}), all other traffic dropped"
}

_fw_nft_block_ip() {
    local ip="$1"
    _fw_nft_ensure_table
    nft add rule inet filter input ip saddr "$ip" drop
    nft add rule inet filter output ip daddr "$ip" drop
    ccdc_log success "nft: blocked all traffic from/to ${ip}"
}

_fw_nft_status() {
    echo "=== nftables ruleset ==="
    nft list ruleset 2>/dev/null || echo "(nft not accessible)"
}

_fw_nft_save() {
    nft list ruleset > /etc/nftables.conf
    ccdc_log success "nft rules saved to /etc/nftables.conf"
}

_fw_nft_allow_internet() {
    _fw_nft_ensure_table
    nft add rule inet filter output tcp dport 80 accept
    nft add rule inet filter output tcp dport 443 accept
    nft add rule inet filter output tcp dport 53 accept
    nft add rule inet filter output udp dport 53 accept
    ccdc_log success "nft: outbound 80,443,53 opened"
}

_fw_nft_block_internet() {
    # Remove internet rules by flushing and re-adding (simplest approach)
    ccdc_log info "nft: removing internet access rules"
    # We can't easily delete specific rules by content in nft, so we warn
    ccdc_log warn "nft: use 'ccdc fw allow-only-in' to rebuild clean rules, or 'ccdc fw status' + manual nft delete"
    ccdc_log info "Attempting to delete outbound 80,443,53 handles..."
    # Try deleting by iterating handles (best-effort)
    for port in 80 443; do
        local handle
        handle="$(nft -a list chain inet filter output 2>/dev/null | grep "tcp dport ${port} accept" | awk '{print $NF}')" || true
        [[ -n "$handle" ]] && nft delete rule inet filter output handle "$handle" 2>/dev/null || true
    done
    for port in 53; do
        for proto in tcp udp; do
            local handle
            handle="$(nft -a list chain inet filter output 2>/dev/null | grep "${proto} dport ${port} accept" | awk '{print $NF}')" || true
            [[ -n "$handle" ]] && nft delete rule inet filter output handle "$handle" 2>/dev/null || true
        done
    done
    ccdc_log success "nft: outbound 80,443,53 closed (best-effort)"
}

# ══════════════════════════════════════════════
# UFW Backend
# ══════════════════════════════════════════════

_fw_ufw_on() {
    ccdc_log info "Enabling ufw..."
    for svc in firewalld nftables; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    done
    ufw --force enable
    ccdc_log success "ufw enabled"
}

_fw_ufw_allow_in() {
    local port="$1" proto="${2:-tcp}"
    ufw allow in "$port/$proto"
    ccdc_log success "ufw: allowed inbound ${port}/${proto}"
}

_fw_ufw_block_in() {
    local port="$1" proto="${2:-tcp}"
    ufw deny in "$port/$proto"
    ccdc_log success "ufw: blocked inbound ${port}/${proto}"
}

_fw_ufw_allow_out() {
    local port="$1" proto="${2:-tcp}"
    ufw allow out "$port/$proto"
    ccdc_log success "ufw: allowed outbound ${port}/${proto}"
}

_fw_ufw_block_out() {
    local port="$1" proto="${2:-tcp}"
    ufw deny out "$port/$proto"
    ccdc_log success "ufw: blocked outbound ${port}/${proto}"
}

_fw_ufw_drop_all_in() {
    ufw default deny incoming
    ccdc_log success "ufw: default deny incoming"
}

_fw_ufw_drop_all_out() {
    ufw default deny outgoing
    ccdc_log success "ufw: default deny outgoing"
}

_fw_ufw_allow_only_in() {
    local ports="$1"
    # Reset ufw
    ufw --force reset
    ufw --force enable
    ufw default deny incoming
    ufw default deny outgoing
    # Allow loopback (ufw handles this mostly, but be explicit)
    ufw allow in on lo
    ufw allow out on lo
    # Scored TCP ports
    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="$(echo "$port" | tr -d ' ')"
        [[ -z "$port" ]] && continue
        ufw allow in "$port/tcp"
        ccdc_log info "ufw: allowed inbound ${port}/tcp"
    done
    # Scored UDP ports
    if [[ -n "${CCDC_SCORED_UDP:-}" ]]; then
        IFS=',' read -ra udp_list <<< "$CCDC_SCORED_UDP"
        for port in "${udp_list[@]}"; do
            port="$(echo "$port" | tr -d ' ')"
            [[ -z "$port" ]] && continue
            ufw allow in "$port/udp"
            ccdc_log info "ufw: allowed inbound ${port}/udp"
        done
    fi
    ccdc_log success "ufw: allow-only-in applied (${ports}), all other traffic dropped"
}

_fw_ufw_block_ip() {
    local ip="$1"
    ufw deny from "$ip"
    ufw deny to "$ip"
    ccdc_log success "ufw: blocked all traffic from/to ${ip}"
}

_fw_ufw_status() {
    echo "=== UFW Status ==="
    ufw status verbose 2>/dev/null || echo "(ufw not accessible)"
    echo ""
    echo "=== UFW Numbered Rules ==="
    ufw status numbered 2>/dev/null || true
}

_fw_ufw_save() {
    ufw reload
    ccdc_log success "ufw rules reloaded (ufw auto-persists)"
}

_fw_ufw_allow_internet() {
    ufw allow out 80/tcp
    ufw allow out 443/tcp
    ufw allow out 53/tcp
    ufw allow out 53/udp
    ccdc_log success "ufw: outbound 80,443,53 opened"
}

_fw_ufw_block_internet() {
    ufw delete allow out 80/tcp 2>/dev/null || true
    ufw delete allow out 443/tcp 2>/dev/null || true
    ufw delete allow out 53/tcp 2>/dev/null || true
    ufw delete allow out 53/udp 2>/dev/null || true
    ccdc_log success "ufw: outbound 80,443,53 closed"
}

# ══════════════════════════════════════════════
# firewalld Backend
# ══════════════════════════════════════════════

_fw_firewalld_on() {
    ccdc_log info "Enabling firewalld..."
    for svc in ufw nftables; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
    done
    systemctl unmask firewalld 2>/dev/null || true
    systemctl enable --now firewalld
    ccdc_log success "firewalld enabled"
}

_fw_firewalld_allow_in() {
    local port="$1" proto="${2:-tcp}"
    firewall-cmd --permanent --add-port="${port}/${proto}"
    firewall-cmd --reload
    ccdc_log success "firewalld: allowed inbound ${port}/${proto}"
}

_fw_firewalld_block_in() {
    local port="$1" proto="${2:-tcp}"
    firewall-cmd --permanent --remove-port="${port}/${proto}" 2>/dev/null || true
    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 port port=${port} protocol=${proto} drop"
    firewall-cmd --reload
    ccdc_log success "firewalld: blocked inbound ${port}/${proto}"
}

_fw_firewalld_allow_out() {
    local port="$1" proto="${2:-tcp}"
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -p "$proto" --dport "$port" -j ACCEPT
    firewall-cmd --reload
    ccdc_log success "firewalld: allowed outbound ${port}/${proto}"
}

_fw_firewalld_block_out() {
    local port="$1" proto="${2:-tcp}"
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -p "$proto" --dport "$port" -j DROP
    firewall-cmd --reload
    ccdc_log success "firewalld: blocked outbound ${port}/${proto}"
}

_fw_firewalld_drop_all_in() {
    firewall-cmd --set-default-zone=drop
    ccdc_log success "firewalld: default zone set to drop"
}

_fw_firewalld_drop_all_out() {
    # firewalld doesn't have native outbound default deny, use direct rules
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -o lo -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 99 -j DROP
    firewall-cmd --reload
    ccdc_log success "firewalld: outbound default drop via direct rules"
}

_fw_firewalld_allow_only_in() {
    local ports="$1"
    # Set drop zone as default
    firewall-cmd --set-default-zone=drop
    # Remove all existing ports from drop zone
    for existing in $(firewall-cmd --zone=drop --list-ports 2>/dev/null); do
        firewall-cmd --permanent --zone=drop --remove-port="$existing" 2>/dev/null || true
    done
    # Add scored TCP ports
    IFS=',' read -ra port_list <<< "$ports"
    for port in "${port_list[@]}"; do
        port="$(echo "$port" | tr -d ' ')"
        [[ -z "$port" ]] && continue
        firewall-cmd --permanent --zone=drop --add-port="${port}/tcp"
        ccdc_log info "firewalld: allowed inbound ${port}/tcp"
    done
    # Scored UDP ports
    if [[ -n "${CCDC_SCORED_UDP:-}" ]]; then
        IFS=',' read -ra udp_list <<< "$CCDC_SCORED_UDP"
        for port in "${udp_list[@]}"; do
            port="$(echo "$port" | tr -d ' ')"
            [[ -z "$port" ]] && continue
            firewall-cmd --permanent --zone=drop --add-port="${port}/udp"
            ccdc_log info "firewalld: allowed inbound ${port}/udp"
        done
    fi
    # Block outbound via direct rules
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -o lo -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 99 -j DROP
    firewall-cmd --reload
    ccdc_log success "firewalld: allow-only-in applied (${ports}), all other traffic dropped"
}

_fw_firewalld_block_ip() {
    local ip="$1"
    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} drop"
    firewall-cmd --reload
    ccdc_log success "firewalld: blocked all traffic from ${ip}"
}

_fw_firewalld_status() {
    echo "=== firewalld State ==="
    firewall-cmd --state 2>/dev/null || echo "(not running)"
    echo ""
    echo "=== Default Zone ==="
    firewall-cmd --get-default-zone 2>/dev/null || true
    echo ""
    echo "=== Active Zones ==="
    firewall-cmd --get-active-zones 2>/dev/null || true
    echo ""
    echo "=== All Zones ==="
    firewall-cmd --list-all-zones 2>/dev/null || true
    echo ""
    echo "=== Direct Rules ==="
    firewall-cmd --direct --get-all-rules 2>/dev/null || true
}

_fw_firewalld_save() {
    firewall-cmd --runtime-to-permanent
    ccdc_log success "firewalld rules persisted"
}

_fw_firewalld_allow_internet() {
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -p tcp --dport 80 -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -p tcp --dport 443 -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -p tcp --dport 53 -j ACCEPT
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -p udp --dport 53 -j ACCEPT
    firewall-cmd --reload
    ccdc_log success "firewalld: outbound 80,443,53 opened"
}

_fw_firewalld_block_internet() {
    firewall-cmd --permanent --direct --remove-rule ipv4 filter OUTPUT 0 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    firewall-cmd --permanent --direct --remove-rule ipv4 filter OUTPUT 0 -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    firewall-cmd --permanent --direct --remove-rule ipv4 filter OUTPUT 0 -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    firewall-cmd --permanent --direct --remove-rule ipv4 filter OUTPUT 0 -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    firewall-cmd --reload
    ccdc_log success "firewalld: outbound 80,443,53 closed"
}

# ══════════════════════════════════════════════
# Public Subcommands
# ══════════════════════════════════════════════

ccdc_firewall_on() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "on"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall on)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch on
    ccdc_undo_log "firewall on -- enabled ${CCDC_FW_BACKEND}, snapshot at ${snapshot_dir}"
}

ccdc_firewall_allow_in() {
    local port="${1:-}"
    local proto="${2:-tcp}"
    if [[ -z "$port" ]]; then
        ccdc_log error "Usage: ccdc firewall allow-in <port> [proto]"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "allow-in"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall allow-in)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch allow_in "$port" "$proto"
    ccdc_undo_log "firewall allow-in ${port}/${proto} -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_block_in() {
    local port="${1:-}"
    local proto="${2:-tcp}"
    if [[ -z "$port" ]]; then
        ccdc_log error "Usage: ccdc firewall block-in <port> [proto]"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "block-in"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall block-in)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch block_in "$port" "$proto"
    ccdc_undo_log "firewall block-in ${port}/${proto} -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_allow_out() {
    local port="${1:-}"
    local proto="${2:-tcp}"
    if [[ -z "$port" ]]; then
        ccdc_log error "Usage: ccdc firewall allow-out <port> [proto]"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "allow-out"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall allow-out)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch allow_out "$port" "$proto"
    ccdc_undo_log "firewall allow-out ${port}/${proto} -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_block_out() {
    local port="${1:-}"
    local proto="${2:-tcp}"
    if [[ -z "$port" ]]; then
        ccdc_log error "Usage: ccdc firewall block-out <port> [proto]"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "block-out"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall block-out)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch block_out "$port" "$proto"
    ccdc_undo_log "firewall block-out ${port}/${proto} -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_drop_all_in() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "drop-all-in"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall drop-all-in)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch drop_all_in
    ccdc_undo_log "firewall drop-all-in -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_drop_all_out() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "drop-all-out"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall drop-all-out)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch drop_all_out
    ccdc_undo_log "firewall drop-all-out -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_allow_only_in() {
    local ports="${1:-${CCDC_SCORED_TCP:-}}"
    if [[ -z "$ports" ]]; then
        ccdc_log error "No ports specified and scored_ports_tcp not set in config"
        ccdc_log info "Usage: ccdc firewall allow-only-in <port1,port2,...>"
        ccdc_log info "Or set: ccdc config set scored_ports_tcp 22,80,443"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "allow-only-in"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall allow-only-in)"
    _fw_save_current_rules "$snapshot_dir"

    ccdc_log info "Applying allow-only-in for ports: ${ports}"
    [[ -n "${CCDC_SCORED_UDP:-}" ]] && ccdc_log info "UDP ports from config: ${CCDC_SCORED_UDP}"

    _fw_dispatch allow_only_in "$ports"
    ccdc_undo_log "firewall allow-only-in ${ports} -- snapshot at ${snapshot_dir}"

    # Handle --activate timer
    _fw_parse_activate "$@" && _fw_activate_timer "$snapshot_dir" "$_FW_ACTIVATE_TIMEOUT"
}

ccdc_firewall_block_ip() {
    local ip="${1:-}"
    if [[ -z "$ip" ]]; then
        ccdc_log error "Usage: ccdc firewall block-ip <ip>"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "block-ip"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall block-ip)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch block_ip "$ip"
    ccdc_undo_log "firewall block-ip ${ip} -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_status() {
    _fw_dispatch status
}

ccdc_firewall_save() {
    _fw_dispatch save
    ccdc_undo_log "firewall save -- rules persisted"
}

ccdc_firewall_allow_internet() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "allow-internet"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall allow-internet)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch allow_internet
    ccdc_undo_log "firewall allow-internet -- snapshot at ${snapshot_dir}"
}

ccdc_firewall_block_internet() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _fw_undo "block-internet"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create firewall block-internet)"
    _fw_save_current_rules "$snapshot_dir"

    _fw_dispatch block_internet
    ccdc_undo_log "firewall block-internet -- snapshot at ${snapshot_dir}"
}

# ── Handler (main router) ──

ccdc_firewall_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_firewall_usage
        return 0
    fi

    case "$cmd" in
        on)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall on"; echo "Enable firewall, disable competing backends"; return 0; }
            ccdc_firewall_on "$@"
            ;;
        allow-in)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall allow-in <port> [proto]"; return 0; }
            ccdc_firewall_allow_in "$@"
            ;;
        block-in)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall block-in <port> [proto]"; return 0; }
            ccdc_firewall_block_in "$@"
            ;;
        allow-out)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall allow-out <port> [proto]"; return 0; }
            ccdc_firewall_allow_out "$@"
            ;;
        block-out)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall block-out <port> [proto]"; return 0; }
            ccdc_firewall_block_out "$@"
            ;;
        drop-all-in)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall drop-all-in"; echo "Default deny all inbound"; return 0; }
            ccdc_firewall_drop_all_in "$@"
            ;;
        drop-all-out)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall drop-all-out"; echo "Default deny all outbound"; return 0; }
            ccdc_firewall_drop_all_out "$@"
            ;;
        allow-only-in)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall allow-only-in <port1,port2,...> [--activate <sec>]"; echo "Drop all except listed ports (inbound+outbound)"; return 0; }
            ccdc_firewall_allow_only_in "$@"
            ;;
        block-ip)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall block-ip <ip>"; return 0; }
            ccdc_firewall_block_ip "$@"
            ;;
        status|show)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall status"; echo "Show current firewall rules"; return 0; }
            ccdc_firewall_status
            ;;
        save)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall save"; echo "Persist rules across reboot"; return 0; }
            ccdc_firewall_save
            ;;
        allow-internet)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall allow-internet"; echo "Open outbound 80,443,53"; return 0; }
            ccdc_firewall_allow_internet "$@"
            ;;
        block-internet)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc firewall block-internet"; echo "Close outbound 80,443,53"; return 0; }
            ccdc_firewall_block_internet "$@"
            ;;
        "")
            ccdc_firewall_usage
            ;;
        *)
            ccdc_log error "Unknown firewall command: ${cmd}"
            ccdc_firewall_usage
            return 1
            ;;
    esac
}
