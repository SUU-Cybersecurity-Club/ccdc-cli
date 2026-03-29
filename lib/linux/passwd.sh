#!/usr/bin/env bash
# ccdc-cli: password management module
# Depends on: common.sh, detect.sh, config.sh, undo.sh

# ── Usage ──

ccdc_passwd_usage() {
    echo -e "${CCDC_BOLD}ccdc passwd${CCDC_NC} — Password management"
    echo ""
    echo "Commands:"
    echo "  list (ls)            List all users with groups, shell, lock status, last login"
    echo "  <username>           Change password for a specific user (interactive)"
    echo "  root                 Change root password"
    echo "  backup-user (bak)    Create backup admin user (default: printer)"
    echo "  lock-all (lock)      Lock all users except root, current, and backup user"
    echo ""
    echo "Options:"
    echo "  --name <name>        Custom backup username (for backup-user)"
    echo "  --keep <u1,u2>       Users to skip when locking (for lock-all)"
    echo "  --undo               Undo the last run of a command"
    echo ""
    echo "Examples:"
    echo "  ccdc pw ls                      List all users"
    echo "  ccdc pw jsmith                  Change jsmith's password"
    echo "  ccdc pw root                    Change root password"
    echo "  ccdc pw bak                     Create 'printer' backup admin"
    echo "  ccdc pw bak --name admin2       Create 'admin2' backup admin"
    echo "  ccdc pw lock                    Lock all non-essential users"
    echo "  ccdc pw lock --keep svc1,svc2   Lock all except listed users"
    echo ""
    echo "Note: ad-change and dsrm are Windows-only commands."
}

# ── List Users ──

ccdc_passwd_list() {
    ccdc_log info "Listing all users..."
    echo ""
    printf "%-16s %-6s %-20s %-30s %-16s %-8s %s\n" \
        "USERNAME" "UID" "HOME" "GROUPS" "SHELL" "LOCKED" "LAST LOGIN"
    printf "%-16s %-6s %-20s %-30s %-16s %-8s %s\n" \
        "--------" "---" "----" "------" "-----" "------" "----------"

    while IFS=: read -r username _ uid _ _ homedir shell; do
        # Skip nologin/false shells for display clarity but still show them
        local groups
        groups="$(id -Gn "$username" 2>/dev/null | tr ' ' ',')"

        # Check locked status
        local locked="no"
        local shadow_status
        shadow_status="$(passwd -S "$username" 2>/dev/null | awk '{print $2}')" || true
        case "$shadow_status" in
            L|LK) locked="YES" ;;
            *) locked="no" ;;
        esac

        # Last login
        local last_login
        last_login="$(lastlog -u "$username" 2>/dev/null | tail -1 | awk '{if ($2 == "**Never") print "Never"; else print $4,$5,$6,$9}')" || true
        [[ -z "$last_login" ]] && last_login="unknown"

        # Highlight admin groups
        local display_groups="$groups"
        if [[ "$groups" == *"sudo"* || "$groups" == *"wheel"* ]]; then
            display_groups="*${groups}"
        fi

        printf "%-16s %-6s %-20s %-30s %-16s %-8s %s\n" \
            "$username" "$uid" "$homedir" "$display_groups" "$shell" "$locked" "$last_login"
    done < /etc/passwd
    echo ""
    echo "* = user has sudo/wheel group membership"
}

# ── Change User Password ──

_passwd_change_backup() {
    local snapshot_dir="$1"
    local user="$2"
    # Save the user's shadow entry for undo
    grep "^${user}:" /etc/shadow > "${snapshot_dir}/shadow.${user}" 2>/dev/null || true
    echo "$user" > "${snapshot_dir}/changed_user"
}

_passwd_change_action() {
    local user="$1"
    local pass1 pass2

    if [[ ! -t 0 ]]; then
        # Non-interactive (piped input for testing)
        read -r pass1
        read -r pass2
    else
        read -rsp "New password for ${user}: " pass1; echo
        read -rsp "Confirm password: " pass2; echo
    fi

    if [[ "$pass1" != "$pass2" ]]; then
        ccdc_log error "Passwords do not match"
        return 1
    fi

    if [[ -z "$pass1" ]]; then
        ccdc_log error "Password cannot be empty"
        return 1
    fi

    echo "${user}:${pass1}" | chpasswd
    ccdc_log success "Password changed for ${user}"
}

_passwd_change_undo() {
    local user="$1"
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_latest passwd "${user}")" || {
        ccdc_log error "No undo snapshot found for passwd ${user}"
        return 1
    }

    local shadow_backup="${snapshot_dir}/shadow.${user}"
    if [[ ! -f "$shadow_backup" ]]; then
        ccdc_log error "No shadow backup found in ${snapshot_dir}"
        return 1
    fi

    # Restore the shadow line
    local old_line
    old_line="$(cat "$shadow_backup")"
    chattr -i /etc/shadow 2>/dev/null || true
    sed -i "s|^${user}:.*|${old_line}|" /etc/shadow
    ccdc_log success "Password restored for ${user} from snapshot"
    ccdc_undo_log "passwd ${user} -- restored from ${snapshot_dir}"
}

ccdc_passwd_change() {
    local user="$1"

    if [[ -z "$user" ]]; then
        ccdc_log error "Usage: ccdc passwd <username>"
        return 1
    fi

    # Validate user exists
    if ! id "$user" &>/dev/null; then
        ccdc_log error "User '${user}' does not exist"
        return 1
    fi

    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _passwd_change_undo "$user"
        return $?
    fi

    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create passwd "${user}")"
    _passwd_change_backup "$snapshot_dir" "$user"
    _passwd_change_action "$user"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        ccdc_undo_log "passwd ${user} -- snapshot at ${snapshot_dir}"
    fi
    return $rc
}

# ── Change Root Password ──

ccdc_passwd_root() {
    if [[ "${CCDC_HELP:-false}" == true ]]; then
        echo "Usage: ccdc passwd root"
        echo "Changes the root password (interactive prompt)"
        return 0
    fi
    ccdc_passwd_change "root"
}

# ── Create Backup User ──

_passwd_backup_user_undo() {
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_latest passwd backup-user)" || {
        ccdc_log error "No undo snapshot found for backup-user"
        return 1
    }

    local backup_name
    backup_name="$(cat "${snapshot_dir}/backup_username" 2>/dev/null)" || {
        ccdc_log error "Cannot determine backup username from snapshot"
        return 1
    }

    if id "$backup_name" &>/dev/null; then
        userdel -r "$backup_name" 2>/dev/null || userdel "$backup_name"
        ccdc_log success "Removed backup user: ${backup_name}"
        ccdc_undo_log "passwd backup-user -- removed ${backup_name}"
    else
        ccdc_log info "User ${backup_name} does not exist — nothing to undo"
    fi
}

ccdc_passwd_backup_user() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _passwd_backup_user_undo
        return $?
    fi

    # Parse --name flag
    local backup_name="${CCDC_BACKUP_USERNAME:-printer}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) backup_name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Check if user already exists
    if id "$backup_name" &>/dev/null; then
        ccdc_log warn "User '${backup_name}' already exists"
        return 0
    fi

    # Determine admin group
    local admin_group
    case "$CCDC_OS_FAMILY" in
        debian) admin_group="sudo" ;;
        rhel)   admin_group="wheel" ;;
        *)      admin_group="sudo" ;;
    esac

    # Create user
    ccdc_log info "Creating backup user: ${backup_name} (group: ${admin_group})"

    useradd -m -s /bin/bash "$backup_name" || {
        ccdc_log error "Failed to create user ${backup_name}"
        return 1
    }
    usermod -aG "$admin_group" "$backup_name" || {
        ccdc_log warn "Failed to add ${backup_name} to ${admin_group}"
    }

    # Set password
    local pass1 pass2
    if [[ ! -t 0 ]]; then
        read -r pass1
        read -r pass2
    else
        read -rsp "Password for ${backup_name}: " pass1; echo
        read -rsp "Confirm password: " pass2; echo
    fi

    if [[ "$pass1" != "$pass2" ]]; then
        ccdc_log error "Passwords do not match"
        userdel -r "$backup_name" 2>/dev/null || true
        return 1
    fi

    echo "${backup_name}:${pass1}" | chpasswd

    # Save to undo snapshot
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create passwd backup-user)"
    echo "$backup_name" > "${snapshot_dir}/backup_username"

    ccdc_undo_log "passwd backup-user -- created ${backup_name}"
    ccdc_log success "Backup user '${backup_name}' created and added to ${admin_group}"
    id "$backup_name"
}

# ── Lock All Users ──

_passwd_lock_all_undo() {
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_latest passwd lock-all)" || {
        ccdc_log error "No undo snapshot found for lock-all"
        return 1
    }

    local locked_file="${snapshot_dir}/locked_by_us.txt"
    if [[ ! -f "$locked_file" ]]; then
        ccdc_log error "No locked user list in snapshot"
        return 1
    fi

    local count=0
    while IFS= read -r user; do
        usermod -U "$user" 2>/dev/null && {
            ccdc_log info "Unlocked: ${user}"
            ((count++))
        }
    done < "$locked_file"

    ccdc_log success "Unlocked ${count} users"
    ccdc_undo_log "passwd lock-all -- unlocked ${count} users from ${snapshot_dir}"
}

ccdc_passwd_lock_all() {
    if [[ "${CCDC_UNDO:-false}" == true ]]; then
        _passwd_lock_all_undo
        return $?
    fi

    # Build exclusion list
    local -a exclusions=("root" "$(whoami)")

    # Add backup username
    [[ -n "${CCDC_BACKUP_USERNAME:-}" ]] && exclusions+=("$CCDC_BACKUP_USERNAME")

    # Add from config
    if [[ -n "${CCDC_PASSWD_KEEP_UNLOCKED:-}" ]]; then
        IFS=',' read -ra keep_list <<< "$CCDC_PASSWD_KEEP_UNLOCKED"
        exclusions+=("${keep_list[@]}")
    fi

    # Parse --keep flag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep)
                IFS=',' read -ra keep_flag <<< "$2"
                exclusions+=("${keep_flag[@]}")
                shift 2
                ;;
            *) shift ;;
        esac
    done

    # Deduplicate exclusions
    local -A excl_map
    for e in "${exclusions[@]}"; do
        excl_map["$e"]=1
    done

    ccdc_log info "Exclusions: ${!excl_map[*]}"

    # Create snapshot
    local snapshot_dir
    snapshot_dir="$(ccdc_undo_snapshot_create passwd lock-all)"

    # Lock users
    local count=0
    while IFS=: read -r username _ uid _ _ _ shell; do
        # Skip excluded users
        [[ -n "${excl_map[$username]+_}" ]] && continue

        # Skip users with nologin/false shells (already can't login)
        [[ "$shell" == */nologin || "$shell" == */false ]] && continue

        # Skip already locked users
        local status
        status="$(passwd -S "$username" 2>/dev/null | awk '{print $2}')" || continue
        [[ "$status" == "L" || "$status" == "LK" ]] && continue

        # Lock the user
        usermod -L "$username" 2>/dev/null && {
            echo "$username" >> "${snapshot_dir}/locked_by_us.txt"
            ccdc_log info "Locked: ${username}"
            ((count++))
        }
    done < /etc/passwd

    ccdc_undo_log "passwd lock-all -- locked ${count} users, snapshot at ${snapshot_dir}"
    ccdc_log success "Locked ${count} users (excluded: ${!excl_map[*]})"
}

# ── Handler (main router) ──

ccdc_passwd_handler() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    if [[ "${CCDC_HELP:-false}" == true && -z "$cmd" ]]; then
        ccdc_passwd_usage
        return 0
    fi

    case "$cmd" in
        list|ls)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc passwd list"; return 0; }
            ccdc_passwd_list "$@"
            ;;
        root)
            ccdc_passwd_root "$@"
            ;;
        backup-user|bak)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc passwd backup-user [--name <name>]"; return 0; }
            ccdc_passwd_backup_user "$@"
            ;;
        lock-all|lock)
            [[ "${CCDC_HELP:-false}" == true ]] && { echo "Usage: ccdc passwd lock-all [--keep <user1,user2>]"; return 0; }
            ccdc_passwd_lock_all "$@"
            ;;
        ad-change|ad)
            ccdc_log error "ad-change is a Windows-only command"
            return 1
            ;;
        dsrm)
            ccdc_log error "dsrm is a Windows-only command"
            return 1
            ;;
        "")
            ccdc_passwd_usage
            ;;
        *)
            # Treat any unrecognized subcommand as a username
            ccdc_passwd_change "$cmd" "$@"
            ;;
    esac
}
