#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$site = Join-Path $repo 'site'
$findings = @()
$patterns = [ordered]@{
    '\bfetch\s*\(' = 'fetch'
    '\b(?:new\s+)?XMLHttpRequest\s*\(' = 'XMLHttpRequest'
    '\bWebSocket\s*\(' = 'WebSocket'
    '\bEventSource\s*\(' = 'EventSource'
    '\bsendBeacon\s*\(' = 'sendBeacon'
    '\bimport\s*\(' = 'dynamic import'
    '<script[^>]+src\s*=\s*["'']https?://' = 'external script'
    '<link[^>]+href\s*=\s*["'']https?://' = 'external stylesheet'
    '<(?:img|iframe|audio|video|source)[^>]+src\s*=\s*["'']https?://' = 'external media'
    '<form[^>]+action\s*=\s*["'']https?://' = 'external form action'
    'url\s*\(\s*["'']?https?://' = 'external CSS asset'
}
foreach ($file in @(Get-ChildItem $site -Recurse -File -Include *.js,*.html,*.css)) {
    $text = Get-Content $file.FullName -Raw
    foreach ($entry in $patterns.GetEnumerator()) {
        if ($text -match $entry.Key) {
            $findings += [pscustomobject]@{
                file = $file.FullName.Substring($repo.Length).TrimStart('\', '/')
                policy = $entry.Value
            }
        }
    }
}
if ($findings.Count -gt 0) {
    $findings | Format-Table -AutoSize
    throw 'The static wizard contains a forbidden network primitive.'
}
Write-Host 'Site no-network policy passed.'
