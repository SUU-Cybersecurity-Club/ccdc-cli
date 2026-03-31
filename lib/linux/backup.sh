#!/usr/bin/env bash
# ccdc-cli: backup module
# Depends on: common.sh, detect.sh, config.sh, undo.sh

# ── Usage ──

ccdc_backup_usage() {
    echo -e "${CCDC_BOLD}ccdc backup${CCDC_NC} — Backup and restore"
    echo ""
    echo "Commands:"
    echo "  etc                  Backup /etc directory"
    echo "  binaries (bin)       Backup /usr/bin and /usr/sbin"
    echo "  web                  Backup /var/www/html and /opt web content"
    echo "  services (svc)       Save service list snapshot"
    echo "  ip                   Save IP addresses and routes"
    echo "  ports                Save listening ports"
    echo "  db                   Dump MySQL/MariaDB databases"
    echo "  full (all)           Run all backup commands"
    echo "  restore              Restore a specific backup by path"
    echo "  list (ls)            List all backups with sizes"
    echo ""
    echo "Options:"
    echo "  --help"
    echo "  -h                   Show help"
    echo "  --undo               Restore from backup"
    echo "  --password <pass>    MySQL password (for db backup)"
    echo ""
    echo "Examples:"
    echo "  ccdc bak etc                    Backup /etc"
    echo "  ccdc bak bin                    Backup system binaries"
    echo "  ccdc bak web                    Backup web content"
    echo "  ccdc bak db --password secret   Dump all MySQL databases"
    echo "  ccdc bak full                   Run all backups"
    echo "  ccdc bak ls                     List existing backups"
    echo "  ccdc bak restore /ccdc-backups/ettc.tar"
    echo "  ccdc bak etc --undo             Restore /etc from backup"
}

# ── Internal Helpers ──

_backup_create_manifest() {
    local filepath="$1"
    local dir basename manifest
    dir="$(dirname "$filepath")"
    basename="$(basename "$filepath")"
    manifest="${dir}/.${basename}.sha256"
    sha256sum "$filepath" > "$manifest" 2>/dev/null || return 0
    ccdc_make_immutable "$manifest"
}

_backup_verify_manifest() {
    local filepath="$1"
    local dir basename manifest
    dir="$(dirname "$filepath")"
    basename="$(basename "$filepath")"
    manifest="${dir}/.${basename}.sha256"
    if [[ ! -f "$manifest" ]]; then
        ccdc_log warn "No SHA256 manifest found for ${basename}"
        return 0
    fi
    chattr -i "$manifest" 2>/dev/null || true
    if sha256sum -c "$manifest" &>/dev/null; then
        ccdc_log info "Integrity check passed for ${basename}"
        ccdc_make_immutable "$manifest"
        return 0
    else
        ccdc_log error "Integrity check FAILED for ${basename}"
        ccdc_make_immutable "$manifest"
        return 1
    fi
}

_backup_protect() {
    local filepath="$1"
    ccdc_make_immutable "$filepath"
}

_backup_unprotect() {
    local filepath="$1"
    chattr -i "$filepath" 2>/dev/null || true
    # Also unprotect manifest
    local dir basename manifest
    dir="$(dirname "$filepath")"
    basename="$(basename "$filepath")"
    manifest="${dir}/.${basename}.sha256"
    chattr -i "$manifest" 2>/dev/null || true
}

_backup_write() {
    # Common wrapper: unprotect existing, run tar/command, manifest, protect
    local outfile="$1"
    shift
    mkdir -p "$(dirname "$outfile")"
    _backup_unprotect "$outfile"
    "$@"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        _backup_create_manifest "$outfile"
        _backup_protect "$outfile"
    fi
    return $rc
}

# ── Backup /etc ──

_backup_etc_undo() {
    local archive="${CCDC_BACKUP_DIR}/ettc.tar"
    if [[ ! -f "$archive" ]]; then
        ccdc_log error "No /etc backup found at ${archive}"
        return 1
    fi
    _backup_verify_manifest "$archive" || return 1
    _backup_unprotect "$archive"
    tar -xpf "$archive" -C / 2>/dev/null
    _backup_protect "$archive"
    ccdc_log success "Restored /etc from ${archive}"
    ccdc_undo_log "backup etc -- restored from ${archive}"
}

ccdc_backup_etc() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _backup_etc_undo
        return $?
    fi

    local outfile="${CCDC_BACKUP_DIR}/ettc.tar"
    ccdc_log info "Backing up /etc..."
    _backup_write "$outfile" tar -cpf "$outfile" /etc 2>/dev/null
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        local size
        size="$(du -sh "$outfile" 2>/dev/null | cut -f1)"
        ccdc_undo_log "backup etc -- ${outfile} (${size})"
        ccdc_log success "Backed up /etc to ${outfile} (${size})"
    else
        ccdc_log error "Failed to backup /etc"
    fi
    return $rc
}

# ── Backup Binaries ──

_backup_binaries_undo() {
    local archive="${CCDC_BACKUP_DIR}/usrr_biin.tar"
    if [[ ! -f "$archive" ]]; then
        ccdc_log error "No binaries backup found at ${archive}"
        return 1
    fi
    _backup_verify_manifest "$archive" || return 1
    _backup_unprotect "$archive"
    tar -xpf "$archive" -C / 2>/dev/null
    _backup_protect "$archive"
    ccdc_log success "Restored binaries from ${archive}"
    ccdc_undo_log "backup binaries -- restored from ${archive}"
}

ccdc_backup_binaries() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _backup_binaries_undo
        return $?
    fi

    local outfile="${CCDC_BACKUP_DIR}/usrr_biin.tar"
    ccdc_log info "Backing up /usr/bin and /usr/sbin..."
    _backup_write "$outfile" tar -cpf "$outfile" /usr/bin /usr/sbin 2>/dev/null
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        local size
        size="$(du -sh "$outfile" 2>/dev/null | cut -f1)"
        ccdc_undo_log "backup binaries -- ${outfile} (${size})"
        ccdc_log success "Backed up binaries to ${outfile} (${size})"
    else
        ccdc_log error "Failed to backup binaries"
    fi
    return $rc
}

# ── Backup Web ──

_backup_web_undo() {
    local restored=0
    local archive="${CCDC_BACKUP_DIR}/httml.tar"
    if [[ -f "$archive" ]]; then
        _backup_verify_manifest "$archive" || return 1
        _backup_unprotect "$archive"
        tar -xpf "$archive" -C / 2>/dev/null
        _backup_protect "$archive"
        ccdc_log success "Restored /var/www/html from ${archive}"
        restored=1
    fi

    local opt_archive="${CCDC_BACKUP_DIR}/oppt.tar"
    if [[ -f "$opt_archive" ]]; then
        _backup_verify_manifest "$opt_archive" || return 1
        _backup_unprotect "$opt_archive"
        tar -xpf "$opt_archive" -C / 2>/dev/null
        _backup_protect "$opt_archive"
        ccdc_log success "Restored /opt from ${opt_archive}"
        restored=1
    fi

    if [[ $restored -eq 0 ]]; then
        ccdc_log error "No web backups found"
        return 1
    fi
    ccdc_undo_log "backup web -- restored"
}

ccdc_backup_web() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _backup_web_undo
        return $?
    fi

    local backed_up=0

    if [[ -d /var/www/html ]]; then
        local outfile="${CCDC_BACKUP_DIR}/httml.tar"
        ccdc_log info "Backing up /var/www/html..."
        _backup_write "$outfile" tar -cpf "$outfile" /var/www/html 2>/dev/null
        if [[ $? -eq 0 ]]; then
            local size
            size="$(du -sh "$outfile" 2>/dev/null | cut -f1)"
            ccdc_undo_log "backup web -- httml.tar (${size})"
            ccdc_log success "Backed up /var/www/html (${size})"
            backed_up=1
        fi
    fi

    if [[ -d /opt ]] && find /opt -maxdepth 2 \( -name "*.html" -o -name "*.php" -o -name "*.py" -o -name "*.js" \) -print -quit 2>/dev/null | grep -q .; then
        local opt_outfile="${CCDC_BACKUP_DIR}/oppt.tar"
        ccdc_log info "Backing up /opt (web content detected)..."
        _backup_write "$opt_outfile" tar -cpf "$opt_outfile" /opt 2>/dev/null
        if [[ $? -eq 0 ]]; then
            local size
            size="$(du -sh "$opt_outfile" 2>/dev/null | cut -f1)"
            ccdc_undo_log "backup web -- oppt.tar (${size})"
            ccdc_log success "Backed up /opt (${size})"
            backed_up=1
        fi
    fi

    if [[ $backed_up -eq 0 ]]; then
        ccdc_log info "No web content found to back up — skipping"
    fi
    return 0
}

# ── Backup Services ──

ccdc_backup_services() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        ccdc_log info "Services snapshot is informational — nothing to undo"
        return 0
    fi

    local outfile="${CCDC_BACKUP_DIR}/svcc_lisst.txt"
    mkdir -p "$CCDC_BACKUP_DIR"
    _backup_unprotect "$outfile"

    ccdc_log info "Saving service list..."
    {
        echo "=== Active Services ==="
        systemctl list-units --type=service --all 2>/dev/null || true
        echo ""
        echo "=== Service Unit Files ==="
        systemctl list-unit-files --type=service 2>/dev/null || true
    } > "$outfile"

    _backup_create_manifest "$outfile"
    _backup_protect "$outfile"
    ccdc_undo_log "backup services -- ${outfile}"
    ccdc_log success "Service list saved to ${outfile}"
}

# ── Backup IP ──

ccdc_backup_ip() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        ccdc_log info "IP snapshot is informational — nothing to undo"
        return 0
    fi

    local outfile="${CCDC_BACKUP_DIR}/ipp_addrs.txt"
    mkdir -p "$CCDC_BACKUP_DIR"
    _backup_unprotect "$outfile"

    ccdc_log info "Saving IP configuration..."
    {
        echo "=== IP Addresses ==="
        ip a 2>/dev/null || ifconfig 2>/dev/null || true
        echo ""
        echo "=== Routes ==="
        ip r 2>/dev/null || route -n 2>/dev/null || true
        echo ""
        echo "=== IPv6 Addresses ==="
        ip -6 a 2>/dev/null || true
        echo ""
        echo "=== DNS Config ==="
        cat /etc/resolv.conf 2>/dev/null || true
    } > "$outfile"

    _backup_create_manifest "$outfile"
    _backup_protect "$outfile"
    ccdc_undo_log "backup ip -- ${outfile}"
    ccdc_log success "IP configuration saved to ${outfile}"
}

# ── Backup Ports ──

ccdc_backup_ports() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        ccdc_log info "Ports snapshot is informational — nothing to undo"
        return 0
    fi

    local outfile="${CCDC_BACKUP_DIR}/prts_snap.txt"
    mkdir -p "$CCDC_BACKUP_DIR"
    _backup_unprotect "$outfile"

    ccdc_log info "Saving port information..."
    {
        echo "=== All Connections ==="
        ss -autpn 2>/dev/null || netstat -autpn 2>/dev/null || true
        echo ""
        echo "=== Listening Only ==="
        ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null || true
    } > "$outfile"

    _backup_create_manifest "$outfile"
    _backup_protect "$outfile"
    ccdc_undo_log "backup ports -- ${outfile}"
    ccdc_log success "Port information saved to ${outfile}"
}

# ── Backup Database ──

_backup_db_undo() {
    local dump="${CCDC_BACKUP_DIR}/dbb_dmpp.sql"
    if [[ ! -f "$dump" ]]; then
        ccdc_log error "No database backup found at ${dump}"
        return 1
    fi
    _backup_verify_manifest "$dump" || return 1
    _backup_unprotect "$dump"

    ccdc_log info "Restoring databases from ${dump}..."
    mysql < "$dump" 2>/dev/null
    local rc=$?
    _backup_protect "$dump"
    if [[ $rc -eq 0 ]]; then
        ccdc_log success "Databases restored from ${dump}"
        ccdc_undo_log "backup db -- restored from ${dump}"
    else
        ccdc_log error "Failed to restore databases"
    fi
    return $rc
}

ccdc_backup_db() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _backup_db_undo
        return $?
    fi

    if ! command -v mysqldump &>/dev/null; then
        ccdc_log info "MySQL/MariaDB not installed — skipping database backup"
        return 0
    fi

    # Parse --password flag
    local db_pass=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --password) db_pass="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local outfile="${CCDC_BACKUP_DIR}/dbb_dmpp.sql"
    mkdir -p "$CCDC_BACKUP_DIR"
    _backup_unprotect "$outfile"

    ccdc_log info "Dumping all databases..."
    local mysql_args="--all-databases"
    if [[ -n "$db_pass" ]]; then
        mysql_args="-p${db_pass} ${mysql_args}"
    fi

    mysqldump $mysql_args > "$outfile" 2>/dev/null
    local rc=$?
    if [[ $rc -eq 0 && -s "$outfile" ]]; then
        _backup_create_manifest "$outfile"
        _backup_protect "$outfile"
        local size
        size="$(du -sh "$outfile" 2>/dev/null | cut -f1)"
        ccdc_undo_log "backup db -- ${outfile} (${size})"
        ccdc_log success "Database dump saved to ${outfile} (${size})"
    else
        ccdc_log error "Failed to dump databases (is MySQL running?)"
        rm -f "$outfile" 2>/dev/null
        return 1
    fi
}

# ── Backup Full ──

ccdc_backup_full() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        ccdc_log info "Use --undo on individual backup commands (e.g. ccdc bak etc --undo)"
        return 0
    fi

    ccdc_log info "Running full backup..."
    local failed=0 total=0 succeeded=0

    for cmd in etc binaries web services ip ports db; do
        total=$((total + 1))
        ccdc_log info "--- backup ${cmd} ---"
        if "ccdc_backup_${cmd}" "$@"; then
            succeeded=$((succeeded + 1))
        else
            failed=$((failed + 1))
            ccdc_log warn "backup ${cmd} had issues (continuing)"
        fi
        echo ""
    done

    ccdc_undo_log "backup full -- ${succeeded}/${total} succeeded"
    if [[ $failed -eq 0 ]]; then
        ccdc_log success "Full backup complete: ${succeeded}/${total} succeeded"
    else
        ccdc_log warn "Full backup complete: ${succeeded}/${total} succeeded, ${failed} had issues"
    fi
}

# ── Backup Restore ──

ccdc_backup_restore() {
    local archive="${1:-}"

    if [[ -z "$archive" ]]; then
        ccdc_log error "Usage: ccdc backup restore <archive-path>"
        return 1
    fi

    if [[ ! -f "$archive" ]]; then
        ccdc_log error "File not found: ${archive}"
        return 1
    fi

    _backup_verify_manifest "$archive" || {
        ccdc_log warn "Manifest verification failed — proceeding anyway"
    }

    _backup_unprotect "$archive"

    case "$archive" in
        *.tar)
            ccdc_log info "Restoring tar archive: ${archive}"
            tar -xpf "$archive" -C / 2>/dev/null
            ;;
        *.tar.gz|*.tgz)
            ccdc_log info "Restoring compressed tar: ${archive}"
            tar -xpzf "$archive" -C / 2>/dev/null
            ;;
        *.sql)
            ccdc_log info "Restoring SQL dump: ${archive}"
            mysql < "$archive" 2>/dev/null
            ;;
        *.sql.gz)
            ccdc_log info "Restoring compressed SQL dump: ${archive}"
            zcat "$archive" | mysql 2>/dev/null
            ;;
        *)
            ccdc_log error "Unknown archive type: ${archive}"
            _backup_protect "$archive"
            return 1
            ;;
    esac

    local rc=$?
    _backup_protect "$archive"
    if [[ $rc -eq 0 ]]; then
        ccdc_log success "Restored from ${archive}"
        ccdc_undo_log "backup restore -- restored ${archive}"
    else
        ccdc_log error "Restore failed for ${archive}"
    fi
    return $rc
}

# ── Backup List ──

ccdc_backup_ls() {
    if [[ ! -d "$CCDC_BACKUP_DIR" ]]; then
        ccdc_log info "No backup directory found at ${CCDC_BACKUP_DIR}"
        return 0
    fi

    ccdc_log info "Backups in ${CCDC_BACKUP_DIR}:"
    echo ""

    local output=""
    output+="NAME|SIZE|DATE|SHA256"$'\n'
    output+="----|----|----|----- "$'\n'

    local found=0
    while IFS= read -r -d '' file; do
        [[ -d "$file" ]] && continue
        local basename
        basename="$(basename "$file")"
        # Skip hidden files (manifests) and the undo dir
        [[ "$basename" == .* ]] && continue

        local size date sha_status
        size="$(du -sh "$file" 2>/dev/null | cut -f1)"
        date="$(stat -c '%y' "$file" 2>/dev/null | cut -d. -f1)" || \
        date="$(stat -f '%Sm' "$file" 2>/dev/null)" || \
        date="unknown"

        # Check manifest
        local manifest_file
        manifest_file="$(dirname "$file")/.${basename}.sha256"
        if [[ -f "$manifest_file" ]]; then
            chattr -i "$manifest_file" 2>/dev/null || true
            if sha256sum -c "$manifest_file" &>/dev/null; then
                sha_status="PASS"
            else
                sha_status="FAIL"
            fi
            ccdc_make_immutable "$manifest_file"
        else
            sha_status="—"
        fi

        output+="${basename}|${size}|${date}|${sha_status}"$'\n'
        found=1
    done < <(find "$CCDC_BACKUP_DIR" -maxdepth 1 -not -name '.ccdc-undo' -print0 2>/dev/null)

    if [[ $found -eq 0 ]]; then
        ccdc_log info "No backups found"
        return 0
    fi

    if command -v column &>/dev/null; then
        echo "$output" | column -t -s '|'
    else
        echo "$output" | tr '|' '\t'
    fi
}

# ── Handler ──

ccdc_backup_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_backup_usage
        return 0
    fi

    # Ensure backup dir exists
    mkdir -p "${CCDC_BACKUP_DIR}" 2>/dev/null || true

    case "$cmd" in
        etc)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup etc"; echo "Backup /etc directory"; return 0; }
            ccdc_backup_etc "$@"
            ;;
        binaries|bin)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup binaries"; echo "Backup /usr/bin and /usr/sbin"; return 0; }
            ccdc_backup_binaries "$@"
            ;;
        web)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup web"; echo "Backup /var/www/html and /opt web content"; return 0; }
            ccdc_backup_web "$@"
            ;;
        services|svc)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup services"; echo "Save service list snapshot"; return 0; }
            ccdc_backup_services "$@"
            ;;
        ip)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup ip"; echo "Save IP addresses and routes"; return 0; }
            ccdc_backup_ip "$@"
            ;;
        ports)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup ports"; echo "Save listening ports"; return 0; }
            ccdc_backup_ports "$@"
            ;;
        db)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup db [--password <pass>]"; echo "Dump MySQL/MariaDB databases"; return 0; }
            ccdc_backup_db "$@"
            ;;
        full|all)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup full"; echo "Run all backup commands in sequence"; return 0; }
            ccdc_backup_full "$@"
            ;;
        restore)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup restore <archive-path>"; echo "Restore a specific backup by path"; return 0; }
            ccdc_backup_restore "$@"
            ;;
        ls|list)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc backup ls"; echo "List all backups with sizes and integrity status"; return 0; }
            ccdc_backup_ls "$@"
            ;;
        "")
            ccdc_backup_usage
            ;;
        *)
            ccdc_log error "Unknown backup command: ${cmd}"
            ccdc_backup_usage
            return 1
            ;;
    esac
}
