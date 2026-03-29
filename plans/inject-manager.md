# Plan: Inject Manager

## Goal

Add a `ccdc inject` command to help the business team track, assign, and complete injects during competition.

## Why

Injects are ~40% of the CCDC score (per WinterKnight). The business team (inject captain, inject member, IR person, SIEM person) needs a lightweight way to:
- See what injects are active and their deadlines
- Assign injects to team members
- Track completion status
- Access common templates (memos, incident reports, policies)
- Quickly deploy common inject requirements (banners, password policies, backups)

Missouri State's CCDC team has an inject-manager tool — this is inspired by that approach but runs as part of ccdc-cli (no Python dependency).

## How It Fits

Runs on any team member's machine. Stores inject state in a shared file (JSON or plain text) that can be synced via the repo or shared drive.

## CLI Commands

- `ccdc inject list` / `ccdc inj ls` — show all injects with status and assignee
- `ccdc inject add "<description>" --due <time>` / `ccdc inj add` — add new inject
- `ccdc inject assign <id> <person>` / `ccdc inj set` — assign inject to team member
- `ccdc inject done <id>` / `ccdc inj done` — mark inject complete
- `ccdc inject template <type>` / `ccdc inj tpl` — print a template (memo, incident report, password policy, etc.)
- `ccdc inject deploy banner` — shortcut to `ccdc harden banner` (common inject)
- `ccdc inject deploy password-policy` — shortcut to `ccdc harden gpo` (common inject)

## Templates to Bundle

| Template | Use Case |
|----------|----------|
| Memorandum | Formal communication to management |
| Interoffice memo | Internal team communication |
| Incident report | Document security incidents for white team |
| Password policy | Justify password changes to management |
| Acceptable use policy | Common compliance inject |
| Network diagram | Template for documenting network topology |
| Change management | Document changes made during competition |

## Storage

```
ccdc-cli/
|-- .ccdc-injects.json         # Inject state (gitignored, or shared via repo)
|-- templates/
|   |-- memo.md
|   |-- incident-report.md
|   |-- password-policy.md
|   |-- acceptable-use.md
|   `-- change-management.md
```

## Tasks

- [ ] Design inject state file format (JSON or plain key=value)
- [ ] Build `ccdc inject list/add/assign/done` in bash + PowerShell
- [ ] Create template files from past competition examples
- [ ] Test with business team during practice
- [ ] Integrate common inject shortcuts with existing ccdc commands

## Dependencies

- None (pure text/file operations)
- Optional: shared file location for team-wide visibility

## Not MVP

This is post-MVP. For MVP, the business team uses their existing checklist. This tool becomes valuable once the technical CLI is stable and the team wants unified tooling.
