#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$roots = @(
    (Join-Path $repo '.github/workflows'),
    (Join-Path $repo 'factory/templates/.github/workflows')
)
$findings = @()
foreach ($root in $roots) {
    foreach ($file in @(Get-ChildItem $root -Recurse -File -Include *.yml,*.yaml,*.tmpl)) {
        $lineNumber = 0
        foreach ($line in @(Get-Content $file.FullName)) {
            $lineNumber++
            if ($line -notmatch '^\s*uses:\s*(?<reference>[^\s#]+)') { continue }
            $reference = $Matches.reference
            if ($reference.StartsWith('./') -or $reference.StartsWith('docker://')) { continue }
            if ($reference -notmatch '@[0-9a-fA-F]{40}$') {
                $findings += [pscustomobject]@{
                    file = $file.FullName.Substring($repo.Length).TrimStart('\', '/')
                    line = $lineNumber
                    reference = $reference
                }
            }
        }
    }
}
if ($findings.Count -gt 0) {
    $findings | Format-Table -AutoSize
    throw 'Mutable or non-SHA GitHub Action references detected.'
}
Write-Host 'Action pinning policy passed.'
