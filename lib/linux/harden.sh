#!/usr/bin/env bash
# ccdc-cli: hardening module
# Depends on: common.sh, detect.sh, config.sh, undo.sh

# ── Usage ──

ccdc_harden_usage() {
    echo -e "${CCDC_BOLD}ccdc harden${CCDC_NC} — System hardening"
    echo ""
    echo "Commands:"
    echo "  ssh                  Harden sshd_config (no root login, key auth, etc.)"
    echo "  ssh-remove           Remove openssh-server entirely"
    echo "  smb                  Disable SMBv1 / harden Samba"
    echo "  cron                 Backup and disable cron jobs"
    echo "  banner               Set login warning banner"
    echo "  revshell-check       Scan for reverse shells (read-only)"
    echo "  mysql                Secure MySQL/MariaDB installation"
    echo ""
    echo "Windows-only (run on Windows):"
    echo "  anon-login, defender, gpo, updates, kerberos, tls, rdp, spooler"
    echo ""
    echo "Options:"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Examples:"
    echo "  ccdc hrd ssh                    Harden SSH config"
    echo "  ccdc hrd ssh-remove             Remove SSH entirely"
    echo "  ccdc hrd cron                   Disable all cron jobs"
    echo "  ccdc hrd banner                 Set login banner"
    echo "  ccdc hrd revshell-check         Scan for reverse shells"
    echo "  ccdc hrd mysql                  Secure MySQL"
}

# ── SSH Harden ──

ccdc_harden_ssh() {
    local sshd_config="/etc/ssh/sshd_config"

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest harden ssh)" || {
            ccdc_log error "No undo snapshot for harden ssh"
            return 1
        }
        if [[ -f "${snapshot_dir}/sshd_config" ]]; then
            cp "${snapshot_dir}/sshd_config" "$sshd_config"
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
            ccdc_log success "sshd_config restored (undo)"
        fi
        return 0
    fi

    if [[ ! -f "$sshd_config" ]]; then
        ccdc_log warn "sshd_config not found -- SSH may not be installed"
        return 1
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create harden ssh)"
    cp "$sshd_config" "${snapshot_dir}/sshd_config"

    ccdc_log info "Hardening SSH configuration..."

    # Apply hardening settings
    local settings=(
        "PermitRootLogin no"
        "MaxAuthTries 3"
        "X11Forwarding no"
        "AllowTcpForwarding no"
        "PermitEmptyPasswords no"
        "ClientAliveInterval 300"
        "ClientAliveCountMax 2"
        "LoginGraceTime 60"
        "Banner /etc/issue.net"
    )

    for setting in "${settings[@]}"; do
        local key="${setting%% *}"
        # Comment out any existing setting, then append new one
        sed -i "s/^#*\s*${key}\b.*/#${key} (ccdc-disabled)/" "$sshd_config" 2>/dev/null || true
    done

    # Append our settings block
    {
        echo ""
        echo "# === CCDC Hardening ==="
        for setting in "${settings[@]}"; do
            echo "$setting"
        done
    } >> "$sshd_config"

    # Restart SSH
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || {
        ccdc_log error "Failed to restart SSH service"
        return 1
    }

    ccdc_log success "SSH hardened (PermitRootLogin=no, MaxAuthTries=3, X11=off, Banner=on)"
    ccdc_undo_log "harden ssh -- hardened sshd_config, snapshot at ${snapshot_dir}"
}

# ── SSH Remove ──

ccdc_harden_ssh_remove() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        ccdc_log info "Re-installing openssh-server..."
        ccdc_install_pkg openssh-server
        systemctl enable --now sshd 2>/dev/null || systemctl enable --now ssh 2>/dev/null || true
        ccdc_log success "openssh-server re-installed (undo)"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create harden ssh-remove)"

    # Backup sshd_config before removal
    [[ -f /etc/ssh/sshd_config ]] && cp /etc/ssh/sshd_config "${snapshot_dir}/sshd_config"

    ccdc_log info "Removing openssh-server..."
    ccdc_remove_pkg openssh-server
    ccdc_log success "openssh-server removed"
    ccdc_undo_log "harden ssh-remove -- removed openssh-server, snapshot at ${snapshot_dir}"
}

# ── SMB ──

ccdc_harden_smb() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest harden smb)" || {
            ccdc_log error "No undo snapshot for harden smb"
            return 1
        }
        if [[ -f "${snapshot_dir}/smb.conf" ]]; then
            cp "${snapshot_dir}/smb.conf" /etc/samba/smb.conf
            systemctl restart smbd 2>/dev/null || systemctl restart smb 2>/dev/null || true
            ccdc_log success "smb.conf restored (undo)"
        fi
        return 0
    fi

    if ! command -v smbstatus &>/dev/null && [[ ! -f /etc/samba/smb.conf ]]; then
        ccdc_log info "Samba is not installed, nothing to harden"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create harden smb)"
    [[ -f /etc/samba/smb.conf ]] && cp /etc/samba/smb.conf "${snapshot_dir}/smb.conf"

    ccdc_log info "Hardening Samba (disabling SMBv1)..."
    if [[ -f /etc/samba/smb.conf ]]; then
        # Remove existing min protocol settings
        sed -i '/^\s*min protocol\s*=/d' /etc/samba/smb.conf
        sed -i '/^\s*server min protocol\s*=/d' /etc/samba/smb.conf
        # Add under [global]
        sed -i '/^\[global\]/a\   min protocol = SMB2\n   server min protocol = SMB2' /etc/samba/smb.conf
        systemctl restart smbd 2>/dev/null || systemctl restart smb 2>/dev/null || true
        ccdc_log success "SMBv1 disabled (min protocol = SMB2)"
    else
        ccdc_log warn "smb.conf not found"
    fi
    ccdc_undo_log "harden smb -- disabled SMBv1, snapshot at ${snapshot_dir}"
}

# ── Cron ──

ccdc_harden_cron() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest harden cron)" || {
            ccdc_log error "No undo snapshot for harden cron"
            return 1
        }
        # Restore /etc/crontab
        if [[ -f "${snapshot_dir}/crontab" ]]; then
            cp "${snapshot_dir}/crontab" /etc/crontab
        fi
        # Restore user crontabs
        if [[ -d "${snapshot_dir}/user_crontabs" ]]; then
            for f in "${snapshot_dir}/user_crontabs/"*; do
                local user
                user="$(basename "$f")"
                crontab -u "$user" "$f" 2>/dev/null || true
            done
        fi
        # Restore /etc/cron.d/
        if [[ -d "${snapshot_dir}/cron.d" ]]; then
            cp "${snapshot_dir}/cron.d/"* /etc/cron.d/ 2>/dev/null || true
        fi
        ccdc_log success "Cron jobs restored (undo)"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create harden cron)"

    ccdc_log info "Backing up and selectively disabling cron jobs..."

    # Backup /etc/crontab
    cp /etc/crontab "${snapshot_dir}/crontab" 2>/dev/null || true

    # Backup /etc/cron.d/
    mkdir -p "${snapshot_dir}/cron.d"
    cp /etc/cron.d/* "${snapshot_dir}/cron.d/" 2>/dev/null || true

    # Backup user crontabs
    mkdir -p "${snapshot_dir}/user_crontabs"
    while IFS=: read -r username _; do
        local cron_output
        cron_output="$(crontab -l -u "$username" 2>/dev/null)" || continue
        if [[ -n "$cron_output" ]]; then
            echo "$cron_output" > "${snapshot_dir}/user_crontabs/${username}"
        fi
    done < /etc/passwd

    # Track what we disabled
    local disabled_log="${snapshot_dir}/disabled.log"
    touch "$disabled_log"

    # /etc/crontab: only comment out user-added lines, preserve system run-parts
    # System lines match: run-parts /etc/cron.(hourly|daily|weekly|monthly)
    local system_pattern='run-parts\s+/etc/cron\.(hourly|daily|weekly|monthly)'
    local commented=0
    while IFS= read -r line; do
        # Skip blank lines, comments, variable assignments (PATH=, SHELL=, MAILTO=)
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*[A-Z_]+= ]]; then
            echo "$line"
            continue
        fi
        # Preserve system run-parts lines
        if [[ "$line" =~ $system_pattern ]]; then
            echo "$line"
            continue
        fi
        # Comment out everything else (user-added entries)
        echo "#CCDC# ${line}"
        echo "/etc/crontab: ${line}" >> "$disabled_log"
        commented=$((commented + 1))
    done < /etc/crontab > /etc/crontab.tmp && mv /etc/crontab.tmp /etc/crontab
    ccdc_log info "/etc/crontab: commented out ${commented} user entries (preserved system run-parts)"

    # /etc/cron.d/: disable non-system files
    # System files are typically from packages (have package name or known names)
    local system_crond_patterns='^(e2scrub|logrotate|man-db|popularity-contest|apt-compat|dpkg|sysstat|certbot|anacron|0hourly|raid-check|sysstat)$'
    local crond_disabled=0
    for f in /etc/cron.d/*; do
        [[ -f "$f" ]] || continue
        local fname
        fname="$(basename "$f")"
        # Skip .placeholder and known system files
        if [[ "$fname" == ".placeholder" || "$fname" =~ $system_crond_patterns ]]; then
            continue
        fi
        # Comment out non-system cron.d files
        sed -i 's/^\([^#].*\)/#CCDC# \1/' "$f"
        echo "/etc/cron.d/${fname}: commented out" >> "$disabled_log"
        crond_disabled=$((crond_disabled + 1))
        ccdc_log info "Commented out /etc/cron.d/${fname}"
    done
    ccdc_log info "/etc/cron.d/: disabled ${crond_disabled} non-system files"

    # User crontabs: remove for non-system users only (UID >= 1000, not root)
    # Root crontab is preserved since it often has legitimate system maintenance
    local users_disabled=0
    while IFS=: read -r username _ uid _; do
        # Skip system accounts and root
        [[ "$uid" -lt 1000 ]] && continue
        local cron_output
        cron_output="$(crontab -l -u "$username" 2>/dev/null)" || continue
        if [[ -n "$cron_output" ]]; then
            crontab -r -u "$username" 2>/dev/null || true
            echo "user crontab removed: ${username}" >> "$disabled_log"
            users_disabled=$((users_disabled + 1))
            ccdc_log info "Removed crontab for user: ${username}"
        fi
    done < /etc/passwd
    ccdc_log info "User crontabs: removed ${users_disabled} (preserved root and system accounts)"

    # Print summary of what was disabled
    ccdc_log info "=== Disabled cron summary ==="
    cat "$disabled_log"

    ccdc_log success "Cron hardening complete (selective -- system cron preserved)"
    ccdc_undo_log "harden cron -- selectively disabled cron, snapshot at ${snapshot_dir}"
}

# ── Banner ──

ccdc_harden_banner() {
    local banner_text="
*************************************************************
*                    AUTHORIZED USE ONLY                     *
*                                                            *
* This system is for authorized users only. All activity is  *
* monitored and logged. Unauthorized access will be          *
* prosecuted to the full extent of the law.                  *
*************************************************************
"

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        local snapshot_dir
        snapshot_dir="$(ccdc_undo_snapshot_latest harden banner)" || {
            ccdc_log error "No undo snapshot for harden banner"
            return 1
        }
        [[ -f "${snapshot_dir}/issue" ]] && cp "${snapshot_dir}/issue" /etc/issue
        [[ -f "${snapshot_dir}/issue.net" ]] && cp "${snapshot_dir}/issue.net" /etc/issue.net
        [[ -f "${snapshot_dir}/motd" ]] && cp "${snapshot_dir}/motd" /etc/motd
        ccdc_log success "Login banners restored (undo)"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create harden banner)"
    cp /etc/issue "${snapshot_dir}/issue" 2>/dev/null || true
    cp /etc/issue.net "${snapshot_dir}/issue.net" 2>/dev/null || true
    cp /etc/motd "${snapshot_dir}/motd" 2>/dev/null || true

    ccdc_log info "Setting login banners..."
    echo "$banner_text" > /etc/issue
    echo "$banner_text" > /etc/issue.net
    echo "$banner_text" > /etc/motd

    # Set SSH banner if sshd exists
    if [[ -f /etc/ssh/sshd_config ]]; then
        if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
            echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        fi
    fi

    ccdc_log success "Login banners set on /etc/issue, /etc/issue.net, /etc/motd"
    ccdc_undo_log "harden banner -- set banners, snapshot at ${snapshot_dir}"
}

# ── Reverse Shell Check ──

ccdc_harden_revshell_check() {
    ccdc_log info "Scanning for potential reverse shells and backdoors..."
    echo ""

    local found=0

    # Check running processes
    echo "=== Suspicious Processes ==="
    local proc_patterns='(/dev/tcp|/dev/udp|nc -e|nc -c|ncat|bash -i|python.*socket|python.*pty|perl.*socket|ruby.*socket|socat|php.*fsockopen)'
    local suspicious_procs
    suspicious_procs="$(ps -eaf 2>/dev/null | grep -iE "$proc_patterns" | grep -v grep)" || true
    if [[ -n "$suspicious_procs" ]]; then
        echo "$suspicious_procs"
        ((found++))
    else
        echo "  (none found)"
    fi
    echo ""

    # Check crontabs
    echo "=== Suspicious Cron Entries ==="
    local cron_hits=""
    while IFS=: read -r username _; do
        local cron_output
        cron_output="$(crontab -l -u "$username" 2>/dev/null)" || continue
        local cron_matches
        cron_matches="$(echo "$cron_output" | grep -iE "$proc_patterns")" || true
        if [[ -n "$cron_matches" ]]; then
            cron_hits+="  User: ${username}"$'\n'"${cron_matches}"$'\n'
        fi
    done < /etc/passwd
    if [[ -n "$cron_hits" ]]; then
        echo "$cron_hits"
        ((found++))
    else
        echo "  (none found)"
    fi
    echo ""

    # Check temp directories
    echo "=== Suspicious Files in /tmp, /var/tmp, /dev/shm ==="
    local temp_hits=""
    for dir in /tmp /var/tmp /dev/shm; do
        [[ -d "$dir" ]] || continue
        local scripts
        scripts="$(find "$dir" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" -o -name "*.php" -o -executable \) 2>/dev/null)" || true
        if [[ -n "$scripts" ]]; then
            temp_hits+="  ${dir}:"$'\n'"${scripts}"$'\n'
        fi
    done
    if [[ -n "$temp_hits" ]]; then
        echo "$temp_hits"
        ((found++))
    else
        echo "  (none found)"
    fi
    echo ""

    # Check for unusual SUID binaries
    echo "=== SUID Binaries (non-standard) ==="
    local suid_hits
    suid_hits="$(find /usr -perm -4000 -type f 2>/dev/null | grep -vE '(sudo|su|passwd|mount|umount|ping|chsh|chfn|newgrp|gpasswd|pkexec)' )" || true
    if [[ -n "$suid_hits" ]]; then
        echo "$suid_hits"
        ((found++))
    else
        echo "  (none found)"
    fi
    echo ""

    # Check authorized_keys for suspicious entries
    echo "=== SSH authorized_keys ==="
    for homedir in /root /home/*; do
        local akfile="${homedir}/.ssh/authorized_keys"
        if [[ -f "$akfile" ]]; then
            echo "  ${akfile}:"
            cat "$akfile"
            echo ""
        fi
    done
    echo ""

    if [[ "$found" -gt 0 ]]; then
        ccdc_log warn "Found ${found} categories of suspicious items -- review above"
    else
        ccdc_log success "No obvious reverse shells or backdoors found"
    fi
    ccdc_log info "Note: this is a basic scan. Sophisticated backdoors may not be detected."
}

# ── MySQL ──

ccdc_harden_mysql() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        ccdc_log warn "MySQL hardening undo is limited -- restore from database backup if needed"
        ccdc_log info "Run: ccdc backup db --undo"
        return 0
    fi

    if ! command -v mysql &>/dev/null; then
        ccdc_log info "MySQL/MariaDB not installed, nothing to harden"
        return 0
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create harden mysql)"

    ccdc_log info "Securing MySQL/MariaDB..."

    # Delete anonymous users
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    ccdc_log info "Deleted anonymous users"

    # Remove remote root access
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    ccdc_log info "Removed remote root access"

    # Drop test database
    mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    ccdc_log info "Dropped test database"

    # Flush privileges
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    # Prompt for new root password
    if [[ "${CCDC_NO_PROMPT:-false}" != true ]]; then
        echo ""
        read -s -p "Enter new MySQL root password (or press Enter to skip): " mysql_pass
        echo ""
        if [[ -n "$mysql_pass" ]]; then
            mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_pass}';" 2>/dev/null || \
            mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${mysql_pass}');" 2>/dev/null || true
            ccdc_log info "Root password changed"
        fi
    fi

    ccdc_log success "MySQL/MariaDB secured"
    ccdc_undo_log "harden mysql -- secured installation, snapshot at ${snapshot_dir}"
}

# ── Handler ──

ccdc_harden_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_harden_usage
        return 0
    fi

    case "$cmd" in
        ssh)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden ssh"; echo "Harden sshd_config (no root login, MaxAuthTries, etc.)"; return 0; }
            ccdc_harden_ssh "$@"
            ;;
        ssh-remove)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden ssh-remove"; echo "Remove openssh-server entirely"; return 0; }
            ccdc_harden_ssh_remove "$@"
            ;;
        smb)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden smb"; echo "Disable SMBv1 / harden Samba"; return 0; }
            ccdc_harden_smb "$@"
            ;;
        cron)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden cron"; echo "Backup and disable all cron jobs"; return 0; }
            ccdc_harden_cron "$@"
            ;;
        banner)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden banner"; echo "Set login warning banner"; return 0; }
            ccdc_harden_banner "$@"
            ;;
        revshell-check)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden revshell-check"; echo "Scan for reverse shells and backdoors (read-only)"; return 0; }
            ccdc_harden_revshell_check "$@"
            ;;
        mysql)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc harden mysql"; echo "Secure MySQL/MariaDB installation"; return 0; }
            ccdc_harden_mysql "$@"
            ;;
        # Windows-only stubs
        anon-login|defender|gpo|updates|kerberos|tls|rdp|spooler)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "${cmd} is a Windows-only command"; return 0; }
            ccdc_log error "${cmd} is a Windows-only command"
            return 1
            ;;
        "")
            ccdc_harden_usage
            ;;
        *)
            ccdc_log error "Unknown harden command: ${cmd}"
            ccdc_harden_usage
            return 1
            ;;
    esac
}
