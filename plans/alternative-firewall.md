# Plan: Alternative Firewall (Backup When Native Is Broken)

## Goal

Add a fallback firewall option for when iptables/nftables (Linux) or Windows Defender Firewall (Windows) have been tampered with, broken, or removed by red team during competition.

## Why

In past CCDC competitions, red team has:
- Deleted or corrupted iptables/nftables binaries
- Broken Windows Defender Firewall service so it won't start
- Modified firewall rules silently so they appear correct but don't actually filter
- Removed firewall kernel modules
- Corrupted the Windows Firewall registry keys

If the native firewall is broken and you can't fix it fast enough, you need a backup that works independently.

## Options to Evaluate

### Linux

| Option | Pros | Cons |
|--------|------|------|
| **nftables (if iptables broken)** | Already in kernel on newer distros, different binary | May also be targeted |
| **iptables (if nft broken)** | Legacy but reliable, different binary | May also be targeted |
| **Pre-compiled static firewall binary** | Can't be broken by deleting system packages | Need to build/bundle per arch |
| **tc (traffic control)** | Built into iproute2, rarely targeted | Complex syntax, limited filtering |
| **eBPF / XDP firewall** | Kernel-level, very hard to break | Complex, needs tooling |
| **Backup copies of iptables/nft binaries** | Simple — restore from backup | Red team may break again |

### Windows

| Option | Pros | Cons |
|--------|------|------|
| **netsh advfirewall** | Different interface to same engine | If engine is broken, won't help |
| **Windows Filtering Platform (WFP) direct** | Lower level than Defender Firewall, harder to break | Complex API, needs compiled tool |
| **Simplewall** | Open source, uses WFP directly, portable .exe | Third-party, needs to be bundled |
| **TinyWall** | Lightweight, hardens Windows Firewall | Still depends on Windows Firewall service |
| **Port proxy / IP blocking via route** | OS-level, no firewall needed | Limited, only blocks by IP not port |

## Recommended Approach

### Linux — Dual Binary Strategy

1. During `ccdc config init`, backup firewall binaries to `/ccdc-backups/bin/`:
   - Copy `/usr/sbin/iptables`, `/usr/sbin/nft`, related libs
   - Store a known-good ruleset alongside
2. If native firewall is broken:
   - `ccdc firewall recover` — restore binaries from backup, reload rules
3. Bundle a **static-compiled iptables or nft binary** in `bin/linux/` for worst case
4. As absolute last resort: use `tc` or kernel `ip route blackhole` for basic blocking

### Windows — Bundle Simplewall or WFP Tool

1. Bundle **simplewall** portable .exe in `bin/windows/`
   - Uses WFP directly, independent of Windows Defender Firewall service
   - Portable, no install needed
   - Can import/export rules as XML
2. `ccdc firewall recover` on Windows:
   - First try to fix Windows Firewall service (registry repair, service recreate)
   - If that fails, launch simplewall with pre-configured competition rules
3. Also backup `netsh advfirewall export` config during `config init`

## CLI Commands

- `ccdc firewall backup` / `ccdc fw bak` — backup firewall binaries and current ruleset
- `ccdc firewall recover` / `ccdc fw rec` — restore firewall from backup, or fall back to alternative
- `ccdc firewall alt` / `ccdc fw alt` — force-start alternative firewall (simplewall on Windows, static binary on Linux)
- `ccdc firewall alt --undo` — stop alternative firewall, switch back to native

## Tasks

- [ ] Research static-compiling iptables for Ubuntu and Fedora (x86_64)
- [ ] Test simplewall portable on Server 2019 and 2022
- [ ] Add firewall binary backup to `ccdc config init` and `ccdc backup full`
- [ ] Build `ccdc fw recover` for Linux (restore binaries, reload rules)
- [ ] Build `ccdc fw recover` for Windows (repair service, fallback to simplewall)
- [ ] Bundle alternative binaries in `bin/linux/` and `bin/windows/`
- [ ] Write WFP rule export/import script for Windows
- [ ] Test: delete iptables binary, run `ccdc fw recover`, verify rules restored
- [ ] Test: break Windows Firewall service, run `ccdc fw recover`, verify blocking works
- [ ] Add to docs/firewall.md

## Dependencies

- Need to build/download static binaries ahead of time (offline requirement)
- Simplewall needs to be vetted — check license compatibility
- eBPF/XDP is powerful but too complex for MVP, consider for later

## Key Insight

The backup firewall binary should be copied during `config init` before red team has a chance to tamper. The earlier you back up, the more trustworthy the copy. This ties into the existing binary backup strategy (`ccdc backup binaries`).
