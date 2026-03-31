# CLAUDE.md — ccdc-cli

## Project Overview

CCDC competition hardening toolkit. Dual-platform: bash (Linux) + PowerShell (Windows). No external dependencies.

- Linux entry: `ccdc.sh` → sources `lib/linux/<module>.sh`
- Windows entry: `ccdc.ps1` → imports `lib/windows/<module>.psm1`
- Tests: `../ccdc-cli-testing/` using pyinfra

## PowerShell Gotchas

### Angle brackets in double-quoted strings

PowerShell treats `<` as a reserved redirection operator. In double-quoted strings passed to functions, `<` can cause parse errors like:

```
The '<' operator is reserved for future use.
```

**Rule:** Always use **single quotes** for strings containing `<>` in `.psm1` files:

```powershell
# BAD — will cause parse errors
Write-CcdcLog "Usage: ccdc passwd <username>" -Level Error

# GOOD — single quotes prevent < from being parsed as operator
Write-CcdcLog 'Usage: ccdc passwd <username>' -Level Error
```

This applies to `Write-CcdcLog`, `Write-Host`, and any function call where the string contains angle brackets. If the string also needs variable interpolation, use subexpression syntax with single-quoted literals or escape with backtick: `` `< `> ``

### WinRM quoting in pyinfra tests

When pyinfra sends commands over WinRM, they get base64-encoded. Single quotes in Python strings can collide with PowerShell's string parsing. Use Python single quotes on the outside with double quotes for the PowerShell string:

```python
# BAD — single quotes collide
"Set-Content -Path file.txt -Value '<html>content</html>'"

# GOOD — swap quoting
'Set-Content -Path file.txt -Value "<html>content</html>"'
```

## Module Pattern

Every module follows the same structure:
- Linux: `ccdc_<module>_handler()` in `lib/linux/<module>.sh`
- Windows: `Invoke-Ccdc<Module>()` in `lib/windows/<module>.psm1`
- Handler export: `Export-ModuleMember -Function Invoke-Ccdc<Module>`
- Every subcommand checks `CCDC_HELP` and `CCDC_UNDO` before acting
- Use `--help` / `-h` on separate lines (not combined `--help|-h`)
