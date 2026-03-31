#!/usr/bin/env bash
# ccdc-cli bash tab completion
# Source this file: source lib/linux/completions.bash
# Or add to: /etc/bash_completion.d/ccdc

_ccdc_completions() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    # Categories and aliases
    local categories="passwd pw backup bak discover disc service svc firewall fw harden hrd siem install inst net copy-paster cp config cfg undo comp-start"

    # Global flags
    local global_flags="--help -h --undo --no-prompt --dry-run --verbose -v --version"

    # Position 1: category
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$categories $global_flags" -- "$cur"))
        return
    fi

    # Resolve category from position 1
    local category="${words[1]}"
    case "$category" in
        passwd|pw)       category="passwd" ;;
        backup|bak)      category="backup" ;;
        discover|disc)   category="discover" ;;
        service|svc)     category="service" ;;
        firewall|fw)     category="firewall" ;;
        harden|hrd)      category="harden" ;;
        install|inst)    category="install" ;;
        config|cfg)      category="config" ;;
        copy-paster|cp)  category="copy-paster" ;;
    esac

    # Position 2: subcommand based on category
    if [[ $cword -eq 2 ]]; then
        local subcmds=""
        case "$category" in
            passwd)
                subcmds="list root backup-user lock-all" ;;
            backup)
                subcmds="etc binaries web services ip ports db full restore ls" ;;
            discover)
                subcmds="network ports users processes cron services firewall integrity all" ;;
            service)
                subcmds="list stop disable enable cockpit" ;;
            firewall)
                subcmds="on allow-in block-in allow-out block-out drop-all-in drop-all-out allow-only-in block-ip status save allow-internet block-internet" ;;
            harden)
                subcmds="ssh smb cron banner revshell-check anon-login defender gpo updates mysql kerberos tls rdp spooler" ;;
            siem)
                subcmds="wazuh-server wazuh-agent splunk-server splunk-agent suricata zeek snoopy auditd sysmon" ;;
            install)
                subcmds="malwarebytes nmap tmux aide" ;;
            net)
                subcmds="wget curl" ;;
            config)
                subcmds="init set show reset edit setup-completions" ;;
            undo)
                subcmds="log show" ;;
            copy-paster)
                subcmds="--delay --speed" ;;
        esac
        COMPREPLY=($(compgen -W "$subcmds $global_flags" -- "$cur"))
        return
    fi

    # Position 3+: flags and config keys
    if [[ $cword -ge 3 ]]; then
        # config set <key> completion
        if [[ "$category" == "config" && "${words[2]}" == "set" && $cword -eq 3 ]]; then
            local keys="os os_family os_version pkg fw_backend backup_dir wazuh_server_ip splunk_server_ip scored_ports_tcp scored_ports_udp backup_username passwd_keep_unlocked"
            COMPREPLY=($(compgen -W "$keys" -- "$cur"))
            return
        fi

        # config set <key> <value> completion for known keys
        if [[ "$category" == "config" && "${words[2]}" == "set" && $cword -eq 4 ]]; then
            case "${words[3]}" in
                os)          COMPREPLY=($(compgen -W "ubuntu debian fedora centos rocky alma oracle" -- "$cur")) ;;
                os_family)   COMPREPLY=($(compgen -W "debian rhel suse arch" -- "$cur")) ;;
                pkg)         COMPREPLY=($(compgen -W "apt dnf yum zypper pacman" -- "$cur")) ;;
                fw_backend)  COMPREPLY=($(compgen -W "iptables ufw nft firewalld" -- "$cur")) ;;
            esac
            return
        fi

        # Firewall port protocol completion
        if [[ "$category" == "firewall" && "${words[2]}" =~ ^(allow-in|block-in|allow-out|block-out)$ && $cword -eq 4 ]]; then
            COMPREPLY=($(compgen -W "tcp udp" -- "$cur"))
            return
        fi

        # Global flags always available
        COMPREPLY=($(compgen -W "$global_flags" -- "$cur"))
    fi
}

# Register for all invocation forms
complete -F _ccdc_completions ccdc
complete -F _ccdc_completions ccdc.sh
complete -F _ccdc_completions ./ccdc.sh
