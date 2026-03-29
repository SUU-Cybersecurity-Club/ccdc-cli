# Plan: Web Application Firewall (WAF)

## Goal

Add `ccdc install waf` and `ccdc harden waf` commands to deploy a WAF in front of scored HTTP services.

## Why

HTTP services (ecom, webmail, web servers) are the most attacked services in CCDC. A WAF blocks SQL injection, XSS, path traversal, and other OWASP top 10 attacks at the network layer before they reach the app.

## Options to Evaluate

| WAF | Pros | Cons |
|-----|------|------|
| **ModSecurity + Apache** | Well-known, OWASP CRS ruleset, already in public-ccdc-resources | Apache-specific, config is complex |
| **ModSecurity + Nginx** | Lightweight, can reverse-proxy any backend | Module support varies by distro |
| **BunkerWeb** | Docker-based, auto-hardening, web UI | Requires Docker, heavier |
| **Coraza** | Go-based ModSecurity-compatible, modern | Newer, less documentation |

## Recommended Approach

1. **ModSecurity with OWASP CRS** — most universal, works with Apache (which is common in CCDC)
2. Ship pre-configured rules in `bin/linux/modsecurity/`
3. CLI commands:
   - `ccdc install waf` / `ccdc inst waf` — installs ModSecurity + CRS
   - `ccdc harden waf` / `ccdc hrd waf` — enables recommended rules, blocks common attacks
   - `ccdc harden waf --undo` — disables ModSecurity module

## Tasks

- [ ] Research which ModSecurity version works on Ubuntu 24 and Fedora 42
- [ ] Test OWASP CRS with Apache and scored HTTP services (ecom, webmail)
- [ ] Ensure WAF doesn't break legitimate traffic (false positives)
- [ ] Bundle offline CRS ruleset in repo
- [ ] Write `lib/linux/waf.sh` module
- [ ] Add to docs/linux.md

## Dependencies

- Apache or Nginx must be running
- Scored HTTP service must be identified first
