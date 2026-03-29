# Plan: Automated Testing

## Goal

Build a test framework to verify ccdc-cli commands work correctly across all supported distros and Windows versions.

## Why

Every competition uses slightly different OS versions. A command that works on Ubuntu 24 might break on Fedora 42 or Oracle 9. Automated testing catches these issues before competition day.

## Phase 1: Docker-Based Linux Testing (Near-Term)

Use Docker containers to test bash scripts across distros.

### Approach

- One Dockerfile per supported distro
- BATS (Bash Automated Testing System) for test framework
- GitHub Actions CI to run on every push

### Test Matrix

| Distro | Versions |
|--------|----------|
| Ubuntu | 22.04, 24.04 |
| Debian | 11, 12 |
| Fedora | 42+ |
| Oracle Linux | 8, 9 |
| Rocky / AlmaLinux | 8, 9 |

### What to Test

- [ ] OS detection (`detect.sh`) correctly identifies each distro
- [ ] Package manager detection works
- [ ] Firewall backend detection works
- [ ] `passwd` commands run without error
- [ ] `backup` commands create expected files
- [ ] `firewall` commands apply and undo correctly
- [ ] `harden` commands apply and undo correctly
- [ ] `comp-start` runs end-to-end

### Example Test (BATS)

```bash
@test "detect.sh identifies Ubuntu correctly" {
    source lib/linux/detect.sh
    detect_os
    [[ "$OS_FAMILY" == "debian" ]]
    [[ "$PKG_MANAGER" == "apt" ]]
}

@test "firewall allow-in creates rule and undo removes it" {
    source lib/linux/firewall.sh
    ccdc_fw_allow_in 8080 tcp
    iptables -L INPUT -n | grep -q "8080"
    ccdc_fw_allow_in_undo 8080 tcp
    ! iptables -L INPUT -n | grep -q "8080"
}
```

## Phase 2: Proxmox Snapshot Testing (Later)

Full VM testing with real OS installs, networking, and services.

### Approach

- Proxmox VE as hypervisor
- Pre-built VM templates for each OS
- Snapshot before test, run ccdc-cli, verify, rollback to snapshot
- Script the whole cycle with `qm` CLI or Proxmox API

### Test Flow

```
1. Clone VM template
2. Snapshot "clean"
3. Run ccdc comp-start
4. Verify: services running, firewall rules applied, passwords changed
5. Run ccdc comp-start --undo
6. Verify: everything restored
7. Destroy clone
```

### What This Enables

- Test Windows (can't do in Docker)
- Test real firewall rules with actual network traffic
- Test Wazuh agent-to-server connectivity
- Test AD domain joining and GPO application
- Test scored services survive hardening

### VM Templates Needed

| OS | Role |
|----|------|
| Ubuntu 24.04 | Ecom web server (HTTP) |
| Fedora 42 | Webmail (SMTP/POP3) |
| Oracle 9 | Splunk server |
| Windows Server 2019 | AD/DNS, Web (HTTP) |
| Windows Server 2022 | FTP |
| Windows 11 | Workstation |

## Phase 3: Windows PowerShell Testing (Later)

### Approach

- Pester (PowerShell testing framework) for Windows module tests
- Can run in GitHub Actions with Windows runners
- Or run inside Proxmox Windows VMs

### Example Test (Pester)

```powershell
Describe "Firewall module" {
    It "Enables all firewall profiles" {
        . .\lib\windows\firewall.psm1
        Enable-CcdcFirewall
        (Get-NetFirewallProfile -Name Domain).Enabled | Should -Be "True"
        (Get-NetFirewallProfile -Name Public).Enabled | Should -Be "True"
        (Get-NetFirewallProfile -Name Private).Enabled | Should -Be "True"
    }
}
```

## Tasks

- [ ] Set up BATS test framework in `tests/` directory
- [ ] Write Dockerfiles for each supported Linux distro
- [ ] Write basic detection tests
- [ ] Write firewall apply/undo tests
- [ ] Set up GitHub Actions workflow
- [ ] (Later) Set up Proxmox test environment
- [ ] (Later) Write Proxmox test automation scripts
- [ ] (Later) Set up Pester for Windows testing

## Not Part of MVP

This is a post-MVP effort. For MVP, manual testing on 2-3 distros and Windows is sufficient. Automated testing is for reliability as the tool grows.
