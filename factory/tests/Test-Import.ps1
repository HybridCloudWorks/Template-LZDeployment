#Requires -Version 7.0
# Stage 11 brownfield import contract tests. Authored with Stage 11; execution
# was explicitly skipped because the implementation environment lacks binaries.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$entry = Get-Content (Join-Path $repo 'brownfield-import.ps1') -Raw
$shell = Get-Content (Join-Path $repo 'brownfield-import.sh') -Raw
$module = Get-Content (Join-Path $repo 'factory/import/LZFactory.Import.psm1') -Raw
$schema = Get-Content (Join-Path $repo 'factory/import/brownfield-classifications.schema.json') -Raw
$checklist = Get-Content (Join-Path $repo 'USER-CHECKLIST.md') -Raw

$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Stage 11 import static contract ==" -ForegroundColor Cyan
ok 'entry defaults to plan' ($entry -match 'LZ_IMPORT_APPLY')
ok 'shell launcher is strict' ($shell -match 'set -euo pipefail')
ok 'classification file is variable-driven' ($entry -match 'LZ_BROWNFIELD_CLASSIFICATIONS')
ok 'discovery must be read-only' ($module -match 'readOnly=true')
ok 'inconclusive inventory fails closed' ($module -match 'Inaccessible inventory cannot be classified as empty')
ok 'default adopt cannot silently import' ($module -match 'Default Adopt is not sufficient')
ok 'replace generates no mutation' ($module -match 'no mutation was generated')
ok 'terraform import is never executed' (
    $module -match 'executesTerraformImport\s*=\s*\$false' -and
    $module -notmatch '& terraform|Invoke-LzImportCommand'
)
ok 'classification schema pins inventory hash' ($schema -match 'inventorySha256')
ok 'checklist documents stale exception' ($checklist -match 'LZ_IMPORT_ALLOW_STALE')

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
