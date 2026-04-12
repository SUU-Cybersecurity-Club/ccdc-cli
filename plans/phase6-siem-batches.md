# Phase 6 SIEM Build Order

Phase 6 has 9 SIEM subcommands. Build them in 4 batches, not all at once. Each batch is small enough to test end-to-end before moving on.

After each batch: write the pyinfra tests in `ccdc-cli-testing/phase6.py` (and `phase6_windows.py`), run against Ubuntu + Fedora + Windows hosts, and confirm green before starting the next batch.

---

## Batch 1: Lightweight starters

Establishes the SIEM module pattern with simple installs. No external network downloads beyond package manager.

- `ccdc siem snoopy` -- Linux command logger, single package install
- `ccdc siem auditd` -- Linux audit daemon, deploy bundled `99-custom.conf`
- `ccdc siem sysmon` -- Windows event logger, install from bundled `bin/windows/Sysmon.zip` + config xml

**Why first:** Each is one install + one config file. Lets us nail the handler/undo pattern, test the cross-platform module structure, and validate `bin/` bundling before committing to heavier work.

---

## Batch 2: Wazuh stack

The primary SIEM. Everything else integrates with it.

- `ccdc siem wazuh-server` -- Linux only, runs on the monitoring box
- `ccdc siem wazuh-agent` -- Linux (apt/dnf) + Windows (msi from `bin/windows/`)

**Why second:** Wazuh is the default SIEM, has real agent/server config, and Suricata integration in Batch 3 depends on Wazuh's `ossec.conf` being in place. Get this solid first.

---

## Batch 3: Network IDS

Suricata + Zeek for network traffic monitoring. Suricata auto-integrates with the Wazuh built in Batch 2.

- `ccdc siem suricata` -- Linux apt/dnf, Windows requires Npcap + msi. Auto-append eve.json to ossec.conf
- `ccdc siem zeek` -- Linux apt/dnf, configure node.cfg + networks.cfg
- `ccdc siem docker` -- Linux apt/dnf docker install + `systemctl enable --now docker`. Used by `wazuh-server` (Batch 2) which prefers the docker path but currently falls back to native packages when docker is absent. Add a pyinfra test that runs `ccdc siem docker` then `ccdc siem wazuh-server` on a fresh host and verifies the `ccdc-wazuh-manager` container comes up. (May be added later.)

**Why third:** Suricata + Zeek depend on Wazuh existing for log forwarding -- Suricata especially needs the ossec.conf integration to be useful. Docker lives here (not Batch 2) so the Wazuh stack stays minimal; Batch 3 retroactively makes wazuh-server's preferred install path reliable.

---

## Batch 4: Splunk alternatives

Splunk is an alternative to Wazuh. Build last because it's redundant with Batches 2-3 and only needed if a team prefers Splunk over Wazuh.

- `ccdc siem splunk-server` -- Linux only, alternative to wazuh-server
- `ccdc siem splunk-agent` -- Linux + Windows, Splunk Universal Forwarder

**Why last:** No other module depends on Splunk. It's a parallel SIEM stack -- doing it after the Wazuh path is fully tested means we already understand the SIEM module patterns and can move faster.

---

## After Phase 6

- **Phase 6.5:** tmux installer + copy-paster utility
- **Phase 7:** comp-start orchestration (chains everything from phases 1-6, can't be built until SIEM is done)
- **Phase 8:** bundled binaries (offline installers, SHA256 manifest)
