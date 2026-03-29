# Plan: LibreNMS Network Monitoring

## Goal

Add `ccdc install librenmss` command to deploy LibreNMS for network monitoring and device visibility during competition.

## Why

LibreNMS gives a dashboard view of all network devices, bandwidth, alerts, and uptime. During CCDC, it helps the team quickly see when services go down, when bandwidth spikes (possible attack), and what devices are on the network.

## How It Fits

- Runs on the Splunk/monitoring server or a dedicated box
- Uses SNMP to poll devices (firewalls, servers, workstations)
- Web-based dashboard — team can check from any browser
- Alerts when services go down

## Recommended Approach

1. Package a minimal LibreNMS install script for Ubuntu and RHEL
2. Pre-configure SNMP community strings (change defaults during comp)
3. Auto-discover devices on the competition network
4. CLI commands:
   - `ccdc install librenmss` / `ccdc inst lnms` — install LibreNMS server
   - `ccdc install snmp-agent` / `ccdc inst snmp` — install SNMP agent on monitored hosts

## Tasks

- [ ] Test LibreNMS install on Ubuntu 24 and Oracle 9
- [ ] Document SNMP configuration for Palo Alto and Cisco FTD
- [ ] Create minimal dashboard template for CCDC (uptime, bandwidth, alerts)
- [ ] Bundle offline install packages
- [ ] Write `lib/linux/librenmss.sh` module
- [ ] Add to docs

## Dependencies

- Requires a server with web stack (Apache/Nginx, PHP, MariaDB)
- SNMP must be enabled on monitored devices
- Firewall must allow UDP 161 between monitoring server and devices

## Considerations

- LibreNMS is heavy — only deploy if team has enough machines
- May conflict with Splunk for resources on shared server
- SNMP community strings are a security risk if not changed from defaults
