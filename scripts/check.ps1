<#
  check.ps1 - Luau compile gate. Run before shipping ANY .luau change.

  Compiles every project .luau with the toolchain at %TEMP%\luau-check
  (luau-compile.exe). Skips: Cobalt.luau (third-party bundle), Game Dumps
  (decompiled sources), and *-backup files. Exits non-zero on any failure.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $env:TEMP "luau-check\luau-compile.exe"
if (-not (Test-Path $exe)) {
    Write-Host "luau-compile not found at $exe"
    Write-Host "Rebuild the toolchain in %TEMP%\luau-check (luau.zip / regen.py), then re-run."
    exit 2
}
$skip = @("Cobalt.luau", "bridge.luau.v14-backup")
$files = Get-ChildItem $root -Recurse -File -Include *.luau, *.Luau |
    Where-Object {
        $_.FullName -notmatch "\\Game Dumps\\" -and
        $_.FullName -notmatch "\\\.git\\" -and
        $_.Name -notin $skip -and
        $_.Name -notmatch "-backup$"
    }
$fail = 0
foreach ($f in $files) {
    $output = & $exe $f.FullName 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $fail++
        Write-Host ("FAIL  " + $f.FullName.Replace($root + "\", ""))
        Write-Host $output.Trim()
    }
}
Write-Host ("compile gate: {0} files checked, {1} failed" -f $files.Count, $fail)
exit $fail
