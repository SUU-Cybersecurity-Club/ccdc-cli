# SIEM cross-platform fallbacks

Future enhancement to Phase 6 SIEM modules. Not blocking for Batch 1 -- the current implementation covers the vast majority of CCDC images (Ubuntu/Debian/RHEL/Fedora/Rocky/Windows). This doc captures the gaps so they can be addressed in a later batch or as part of Phase 6 polish.

## The gap

`ccdc siem auditd` assumes the standard `/etc/audit/rules.d/` layout and a working kernel audit subsystem. That assumption holds on the common CCDC distros but breaks on:

- **NixOS** -- audit rules are declarative through Nix config; dropping files in `/etc/audit/rules.d/` is a no-op. `auditctl` may exist but the layout is non-standard.
- **Arch** -- `audit` package is in extra, not installed by default. Works if installed, but `ccdc siem auditd` currently does not handle the missing-package case beyond the install fallback.
- **Alpine / musl distros** -- audit userspace is uncommon; minimal images typically skip it.
- **Containers / minimal images** -- the kernel audit subsystem may not be exposed at all, so even a successful install produces no events.

`ccdc siem sysmon` is currently Windows-only stub on Linux. Microsoft ships **Sysmon for Linux** (`sysmonforlinux`) as an eBPF-based port via `packages.microsoft.com`, with the same XML config schema and syslog output. It works on any kernel >= ~4.18 with eBPF support, which is every modern CCDC Linux image.

## Proposed work

Two small additions, ordered by value:

### 1. Auditd preflight check

Before deploying `99-ccdc.rules`, detect whether the host can actually use auditd. Add at the top of `ccdc_siem_auditd` (in `lib/linux/siem.sh`):

- Check `/etc/audit/rules.d/` exists OR `auditctl` is available.
- Check `auditctl -s` returns a kernel-supported state (not `enabled 0`, not `Operation not supported`).
- If either fails, log a warn naming the alternative (`ccdc siem sysmon` once Linux support lands) and exit 0 without writing rules.

This is ~15 lines and removes silent-failure surprises on Nix/Alpine/containers.

### 2. Sysmon for Linux

Promote `ccdc siem sysmon` from Windows-only stub to a real Linux command:

- Detect kernel version >= 4.18 and eBPF availability (`ls /sys/kernel/btf/vmlinux` or `bpftool` if present).
- Install `sysmonforlinux` via the package manager:
  - Debian/Ubuntu: add `packages.microsoft.com` apt repo, `apt-get install sysmonforlinux`.
  - RHEL/Fedora: add `packages.microsoft.com` rpm repo, `dnf install sysmonforlinux`.
  - Bundled fallback (Phase 8): ship `.deb` + `.rpm` in `bin/linux/sysmonforlinux/`.
- Deploy the same `bin/windows/sysmonconfig.xml` (the schema is shared) -- or ship a Linux-specific `bin/linux/sysmonconfig-linux.xml` if rules need divergence.
- Run `sudo sysmon -accepteula -i <config>`.
- Verify via `systemctl status sysmon` and `journalctl -u sysmon | grep -q EventID`.
- Undo: `sudo sysmon -u`, restore prior repo state from snapshot (since adding the MS repo is a real system change worth recording).

This fully covers the Nix/Alpine/container gap and gives teams a unified `ccdc siem sysmon` command on every platform.

## When to do this

Slot after Batch 4 (Splunk) completes, or fold into a Phase 6.5 polish pass. Both items are independent of Wazuh/Suricata/Zeek and don't block any other work. The preflight check (#1) is a 15-minute task and could land standalone any time.

## Out of scope

- Rewriting `99-ccdc.rules` for NixOS-style declarative config -- if a CCDC scenario actually uses NixOS, switching to `sysmonforlinux` is the better path than translating audit rules.
- Auto-detecting between auditd and sysmon-for-linux inside `ccdc siem auditd` -- keep the commands distinct so operators know which logger they're invoking.
