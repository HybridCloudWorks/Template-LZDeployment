#Requires -Version 7.0
# Stage 10 scaffold contract tests. The static text contract below was authored
# with Stage 10 (execution was skipped because the environment lacked the
# binaries); the inventory-execution section at the end actually runs the
# binary-free part of the module, because static matching alone let the Linux
# hidden-file crash reach main (TODO 1.2).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$entry = Get-Content (Join-Path $repo 'scaffold-copy.ps1') -Raw
$shell = Get-Content (Join-Path $repo 'scaffold-copy.sh') -Raw
$module = Get-Content (Join-Path $repo 'factory/scaffold/LZFactory.Scaffold.psm1') -Raw
$checklist = Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw

$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Stage 10 scaffold static contract ==" -ForegroundColor Cyan
ok 'entry is plan-only by default' ($entry -match 'LZ_SCAFFOLD_APPLY')
ok 'shell launcher is strict' ($shell -match 'set -euo pipefail')
ok 'all paths are variable-driven' (
    $entry -match 'LZ_RENDERED_PATH' -and
    $entry -match 'LZ_SCAFFOLD_TARGET' -and
    $entry -match 'LZ_SCAFFOLD_EVIDENCE'
)
ok 'inventory mismatch fails closed' ($module -match 'Rendered inventory mismatch')
ok 'unsafe nested targets fail closed' ($module -match 'must not contain one another')
ok 'non-empty target requires force' ($module -match 'Re-run with -Force')
ok 'existing origin is verified' ($module -match 'Existing origin does not match')
ok 'apply preserves backup' ($module -match 'backupDirectory')
ok 'plan and audit evidence emitted' (
    $module -match 'scaffold-plan\.json' -and $module -match 'scaffold-audit\.json'
)
ok 'user checklist documents scaffold variables' (
    $checklist -match 'LZ_SCAFFOLD_APPLY' -and $checklist -match 'LZ_SCAFFOLD_FORCE'
)
ok 'apply requires the post-render validation report' (
    $module -match 'ValidationReportPath' -and $module -match 'Run \./validate-render\.ps1'
)
ok 'stale validation evidence is rejected' (
    $module -match "'stale'" -and $module -match 'manifestSha256Match'
)
ok 'validation override env is explicit and documented' (
    $module -match 'LZ_SCAFFOLD_ALLOW_UNVALIDATED' -and
    $checklist -match 'LZ_SCAFFOLD_ALLOW_UNVALIDATED'
)

# The static contract above never executes the walk, which is how the Linux
# hidden-file crash (TODO 1.2) reached main: Get-ChildItem -Force enumerated
# .terraform-docs.yml into the inventory, then the per-file Get-Item size read
# — lacking -Force — could not see it and threw. This section runs the real
# Get-LzScaffoldInventory over a temp tree containing a hidden leaf file, so
# the regression fails the suite instead of failing the first Linux operator.
Write-Host "`n== Stage 10 scaffold inventory execution ==" -ForegroundColor Cyan
Import-Module (Join-Path $repo 'factory/scaffold/LZFactory.Scaffold.psm1') -Force
$invRoot = Join-Path $PSScriptRoot '.out/scaffold-inventory-hidden'
if (Test-Path $invRoot) { Remove-Item $invRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $invRoot 'terraform/modules/demo') -Force | Out-Null
Set-Content (Join-Path $invRoot 'terraform/modules/demo/main.tf') '# demo module' -Encoding utf8
Set-Content (Join-Path $invRoot 'terraform/modules/demo/.terraform-docs.yml') 'formatter: markdown table' -Encoding utf8
@{
    files = @(
        @{ Destination = 'terraform/modules/demo/main.tf' }
        @{ Destination = 'terraform/modules/demo/.terraform-docs.yml' }
    )
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $invRoot 'render-manifest.json') -Encoding utf8

$inventory = $null
$inventoryError = $null
try { $inventory = Get-LzScaffoldInventory -RenderedDirectory $invRoot }
catch { $inventoryError = $_.Exception.Message }
ok 'inventory walk executes over hidden leaf files' ($null -eq $inventoryError)
if ($inventoryError) { Write-Host "       error: $inventoryError" -ForegroundColor Yellow }
# @() must wrap the whole if-expression: a branch that emits an empty array
# assigns $null, and $null.Count throws under Set-StrictMode Latest.
$hiddenEntry = @(if ($inventory) {
    $inventory.files | Where-Object { $_.path -eq 'terraform/modules/demo/.terraform-docs.yml' }
})
ok 'hidden file appears in the inventory' ($hiddenEntry.Count -eq 1)
ok 'hidden file size and hash are read' (
    $hiddenEntry.Count -eq 1 -and
    $hiddenEntry[0].bytes -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($hiddenEntry[0].sha256)
)
Remove-Item $invRoot -Recurse -Force

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
