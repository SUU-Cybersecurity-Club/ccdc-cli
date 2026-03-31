# AGENT.md — ccdc-cli

Guidelines for AI agents working on this codebase.

## Critical: PowerShell String Quoting

**Never use double quotes for strings containing `<` or `>` in .psm1 files.**

PowerShell interprets `<` as a redirection operator inside double-quoted strings in certain parsing contexts. This causes cryptic cascade parse failures like:

```
The '<' operator is reserved for future use.
The string is missing the terminator: ".
Missing closing '}' in statement block or type definition.
```

Use single quotes instead:

```powershell
# WRONG
Write-CcdcLog "Usage: ccdc foo <arg>" -Level Error
Write-Host "Usage: ccdc foo <arg>"

# RIGHT
Write-CcdcLog 'Usage: ccdc foo <arg>' -Level Error
Write-Host 'Usage: ccdc foo <arg>'
```

If variable interpolation is needed alongside angle brackets, use:
```powershell
Write-CcdcLog ('Usage: ccdc foo <arg> for ' + $variable) -Level Error
```

## WinRM / pyinfra Test Quoting

Commands sent via pyinfra over WinRM are base64-encoded. Nested single quotes break. In `phase*_windows.py` test files:

```python
# WRONG — nested single quotes collide
"Set-Content -Path file.txt -Value '<html>'"

# RIGHT — Python single quotes outside, PS double quotes inside
'Set-Content -Path file.txt -Value "<html>"'
```

## Module Structure

All modules follow the same pattern. See `lib/linux/passwd.sh` and `lib/windows/passwd.psm1` as the reference implementation.

- Handler function name: `ccdc_<module>_handler` (bash) / `Invoke-Ccdc<Module>` (PS)
- Every subcommand must handle `--help` and `--undo` flags
- Use existing helpers: `ccdc_log`, `ccdc_make_immutable`, `ccdc_undo_snapshot_create`, etc.
- Windows export: `Export-ModuleMember -Function Invoke-Ccdc<Module>`
