# ccdc-cli PowerShell tab completion
# Source this file: . lib\windows\completions.ps1
# Or add to your $PROFILE

$ccdcCategories = @(
    'passwd','pw','backup','bak','discover','disc','service','svc',
    'firewall','fw','harden','hrd','siem','install','inst','net',
    'copy-paster','cp','config','cfg','undo','comp-start'
)

$ccdcSubcommands = @{
    'passwd'      = @('list','root','backup-user','lock-all','ad-change','dsrm')
    'backup'      = @('etc','binaries','web','services','ip','ports','db','full','restore','ls')
    'discover'    = @('network','ports','users','processes','cron','services','firewall','integrity','all')
    'service'     = @('list','stop','disable','enable','cockpit')
    'firewall'    = @('on','allow-in','block-in','allow-out','block-out','drop-all-in','drop-all-out','allow-only-in','block-ip','status','save','allow-internet','block-internet')
    'harden'      = @('ssh','smb','cron','banner','revshell-check','anon-login','defender','gpo','updates','mysql','kerberos','tls','rdp','spooler')
    'siem'        = @('wazuh-server','wazuh-agent','splunk-server','splunk-agent','suricata','zeek','snoopy','auditd','sysmon')
    'install'     = @('malwarebytes','nmap','tmux','aide')
    'net'         = @('wget','curl')
    'config'      = @('init','set','show','reset','edit','setup-completions')
    'undo'        = @('log','show')
    'copy-paster' = @('--delay','--speed')
}

$ccdcConfigKeys = @('os','os_family','os_version','pkg','fw_backend','backup_dir','wazuh_server_ip','splunk_server_ip','scored_ports_tcp','scored_ports_udp','backup_username','passwd_keep_unlocked')

$ccdcConfigValues = @{
    'os'          = @('ubuntu','debian','fedora','centos','rocky','alma','oracle')
    'os_family'   = @('debian','rhel','suse','arch')
    'pkg'         = @('apt','dnf','yum','zypper','pacman')
    'fw_backend'  = @('iptables','ufw','nft','firewalld')
}

# Alias map for resolving short names to canonical
$ccdcAliasMap = @{
    'pw'='passwd'; 'bak'='backup'; 'disc'='discover'; 'svc'='service';
    'fw'='firewall'; 'hrd'='harden'; 'inst'='install'; 'cfg'='config'; 'cp'='copy-paster'
}

Register-ArgumentCompleter -CommandName 'ccdc','ccdc.ps1','.\ccdc.ps1' -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokens = $commandAst.ToString() -split '\s+'
    $tokenCount = $tokens.Count

    # If cursor is at end with trailing space, we're completing the NEXT token
    $trailing = $commandAst.ToString().Substring(0, $cursorPosition)
    if ($trailing.EndsWith(' ')) { $tokenCount++ }

    # Position 2: category completion (token[0] is the script name)
    if ($tokenCount -le 2) {
        $ccdcCategories | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
        return
    }

    # Resolve the category
    $rawCategory = $tokens[1]
    $category = if ($ccdcAliasMap.ContainsKey($rawCategory)) { $ccdcAliasMap[$rawCategory] } else { $rawCategory }

    # Position 3: subcommand completion
    if ($tokenCount -le 3) {
        if ($ccdcSubcommands.ContainsKey($category)) {
            $ccdcSubcommands[$category] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        return
    }

    # Position 4+: context-specific
    $subcommand = $tokens[2]

    # config set <key>
    if ($category -eq 'config' -and $subcommand -eq 'set' -and $tokenCount -le 4) {
        $ccdcConfigKeys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
        return
    }

    # config set <key> <value>
    if ($category -eq 'config' -and $subcommand -eq 'set' -and $tokenCount -le 5) {
        $key = $tokens[3]
        if ($ccdcConfigValues.ContainsKey($key)) {
            $ccdcConfigValues[$key] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        return
    }

    # firewall port protocol
    if ($category -eq 'firewall' -and $subcommand -match '^(allow-in|block-in|allow-out|block-out)$' -and $tokenCount -le 5) {
        @('tcp','udp') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
        return
    }
}
