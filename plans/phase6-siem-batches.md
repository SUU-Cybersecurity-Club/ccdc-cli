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
- `ccdc siem wazuh-archives` -- retroactively turn on full forensics on an already-installed wazuh-server. Red team is hot the entire competition, so we want every event captured, not just level >=3 alerts. This subcommand:
  1. Edits `/var/ossec/etc/ossec.conf` to set `<logall_json>yes</logall_json>` (leave `<logall>no</logall>` -- JSON only, halves disk).
  2. Drops `/etc/logrotate.d/wazuh-archives` with hourly rotation, `rotate 6`, `compress`, `delaycompress`, `copytruncate`, `maxsize 500M`. `copytruncate` is mandatory -- without it analysisd keeps writing to the rotated inode and rotation silently breaks until restart.
  3. Drops `/etc/cron.hourly/wazuh-rotate` that force-runs logrotate (default cadence is daily, too slow).
  4. Drops `/etc/cron.d/wazuh-disk-guard` -- every 5 min, if `/var` is over 85%, delete the 3 oldest `*.gz` archives. Belt-and-suspenders failsafe so disk-fill never takes the SIEM box down.
  5. Restarts `wazuh-manager` so the logall_json change takes effect.
  6. Filebeat archives input enable in `/etc/filebeat/filebeat.yml` (`module: wazuh`, `archives.enabled: true`) so the `wazuh-archives-*` indices actually populate.
  7. Indexer side: ISM policy or hourly cron `curl -XDELETE` against `wazuh-archives-*` older than 6h to keep the indexer from ballooning in parallel.
  - Undo path: revert ossec.conf to `<logall_json>no</logall_json>`, remove the three rotation/guard files, restart wazuh-manager, disable filebeat archives input.
  - Test (`phase6.py`): run `ccdc siem wazuh-server` then `ccdc siem wazuh-archives`, confirm `archives.json` exists and is being written, confirm logrotate config parses (`logrotate -d /etc/logrotate.d/wazuh-archives`), confirm `wazuh-archives-*` index appears in the indexer.

**Why third:** Suricata + Zeek depend on Wazuh existing for log forwarding -- Suricata especially needs the ossec.conf integration to be useful. Docker lives here (not Batch 2) so the Wazuh stack stays minimal; Batch 3 retroactively makes wazuh-server's preferred install path reliable. `wazuh-archives` lives here too (not Batch 2) for the same reason: keep the base wazuh-server install minimal and bolt on the high-volume forensics layer once we're confident the stack is healthy.

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
