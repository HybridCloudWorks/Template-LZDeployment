#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo root resolved from this script's location so the suite runs from
# any checkout, on any machine, from any working directory.
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$repo/factory/discovery/LZFactory.Discovery.psd1" -Force

$script:pass = 0; $script:fail = 0
function ok($name, $cond, $extra = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name $(if($extra){"-> $extra"})" -ForegroundColor Red }
}

Write-Host "`n== 1. CIDR overlap ==" -ForegroundColor Cyan
ok '10.0.0.0/16 vs 10.0.2.0/24 overlap'     (Test-LzCidrOverlap -CidrA '10.0.0.0/16' -CidrB '10.0.2.0/24')
ok '10.0.0.0/16 vs 10.2.0.0/16 disjoint'   (-not (Test-LzCidrOverlap -CidrA '10.0.0.0/16' -CidrB '10.2.0.0/16'))
ok 'identical ranges overlap'               (Test-LzCidrOverlap -CidrA '172.16.0.0/12' -CidrB '172.16.0.0/12')
ok 'adjacent /24s disjoint'                (-not (Test-LzCidrOverlap -CidrA '10.0.0.0/24' -CidrB '10.0.2.0/24'))
ok 'supernet contains subnet'               (Test-LzCidrOverlap -CidrA '10.0.0.0/8' -CidrB '10.255.255.0/24')
ok '0.0.0.0/0 overlaps everything'          (Test-LzCidrOverlap -CidrA '0.0.0.0/0' -CidrB '192.168.1.0/24')
ok 'malformed input is not an overlap'     (-not (Test-LzCidrOverlap -CidrA 'garbage' -CidrB '10.0.0.0/16'))
ok 'out-of-range octet rejected'           (-not (Test-LzCidrOverlap -CidrA '999.0.0.0/8' -CidrB '10.0.0.0/16'))

Write-Host "`n== 2. RBAC wildcard matching ==" -ForegroundColor Cyan
ok '* matches everything'                   (Test-LzWildcardMatch -Pattern '*' -Value 'Microsoft.Network/virtualNetworks/write')
ok 'provider wildcard matches'              (Test-LzWildcardMatch -Pattern 'Microsoft.Network/*' -Value 'Microsoft.Network/virtualNetworks/write')
ok 'wrong provider does not match'         (-not (Test-LzWildcardMatch -Pattern 'Microsoft.Compute/*' -Value 'Microsoft.Network/virtualNetworks/write'))
ok 'exact match'                            (Test-LzWildcardMatch -Pattern 'Microsoft.Authorization/roleAssignments/write' -Value 'Microsoft.Authorization/roleAssignments/write')
ok 'partial prefix does not match'         (-not (Test-LzWildcardMatch -Pattern 'Microsoft.Authorization/roleAssignments' -Value 'Microsoft.Authorization/roleAssignments/write'))
ok 'empty pattern never matches'           (-not (Test-LzWildcardMatch -Pattern '' -Value 'anything'))
ok 'mid-string wildcard'                    (Test-LzWildcardMatch -Pattern 'Microsoft.*/read' -Value 'Microsoft.Network/read')

Write-Host "`n== 3. Read-only guard ==" -ForegroundColor Cyan
$threw = $false
try { Assert-LzReadOnly -Arguments @('group','create','--name','x') } catch { $threw = $true }
ok 'mutating verb "create" is rejected' $threw

$threw = $false
try { Assert-LzReadOnly -Arguments @('role','assignment','delete','--ids','x') } catch { $threw = $true }
ok 'mutating verb "delete" is rejected' $threw

$threw = $false
try { Assert-LzReadOnly -Arguments @('account','list','--all') } catch { $threw = $true }
ok 'read-only "list" is allowed' (-not $threw)

$threw = $false
try { Assert-LzReadOnly -Arguments @('graph','query','-q','Resources | project name') } catch { $threw = $true }
ok 'graph query is allowed' (-not $threw)

Write-Host "`n== 4. Empty vs Forbidden must never collapse ==" -ForegroundColor Cyan
$empty = Invoke-LzProbe -Name 'e' -Probe { @() }
ok 'no results => Empty'          ($empty.Status -eq 'Empty')
ok 'Empty is conclusive'          ($empty.Conclusive -eq $true)

$forbidden = Invoke-LzProbe -Name 'f' -Probe { throw "AuthorizationFailed: does not have authorization" }
ok '403 => Forbidden'             ($forbidden.Status -eq 'Forbidden')
ok 'Forbidden is NOT conclusive'  ($forbidden.Conclusive -eq $false)
ok 'Forbidden count is 0 but distinct from Empty' ($forbidden.Count -eq 0 -and $forbidden.Status -ne $empty.Status)

$unavail = Invoke-LzProbe -Name 'u' -Probe { throw "Please run 'az login' to setup account" }
ok 'not-signed-in => Unavailable' ($unavail.Status -eq 'Unavailable')
ok 'Unavailable is not conclusive' ($unavail.Conclusive -eq $false)

$errp = Invoke-LzProbe -Name 'x' -Probe { throw "something exploded" }
ok 'unknown failure => Error'     ($errp.Status -eq 'Error')
ok 'Error is not conclusive'      ($errp.Conclusive -eq $false)

$okp = Invoke-LzProbe -Name 'o' -Probe { @([pscustomobject]@{A=1}, [pscustomobject]@{A=2}) }
ok 'results => Ok with count'     ($okp.Status -eq 'Ok' -and $okp.Count -eq 2)

Write-Host "`n== 5. Error classification ==" -ForegroundColor Cyan
ok 'AuthorizationFailed'          (Test-LzForbiddenError 'AuthorizationFailed')
ok 'Authorization_RequestDenied'  (Test-LzForbiddenError 'Authorization_RequestDenied: Insufficient privileges')
ok '(403)'                        (Test-LzForbiddenError 'Operation returned (403) Forbidden')
ok 'benign text is not forbidden' (-not (Test-LzForbiddenError 'resource group not found'))
ok 'gh auth login => unavailable' (Test-LzUnavailableError 'To get started with GitHub CLI, please run: gh auth login')

Write-Host "`n== 6. Secret redaction ==" -ForegroundColor Cyan
# NOT A REAL CREDENTIAL. This is the canonical jwt.io sample token — header
# {"alg":"HS256"}, payload {"sub":"1234567890"} — a public test vector present
# only to prove Protect-LzSecretText redacts JWT-shaped strings. Secret scanners
# will flag it; that is the correct behaviour and it is safe to ignore here.
$jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U'
ok 'JWT redacted'        ((Protect-LzSecretText "token=$jwt") -notmatch 'eyJhbGci')
ok 'GitHub PAT redacted' ((Protect-LzSecretText 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345') -notmatch 'ghp_ABCDEF')
ok 'client secret redacted' ((Protect-LzSecretText 'client_secret=SuperSecretValue123') -notmatch 'SuperSecretValue123')
ok 'ordinary text untouched' ((Protect-LzSecretText 'management group mg-contoso') -eq 'management group mg-contoso')
ok 'null-safe (returns empty, never throws)' ('' -eq (Protect-LzSecretText $null))

Write-Host "`n== 7. Markdown cell safety ==" -ForegroundColor Cyan
ok 'pipes escaped'    ((ConvertTo-LzSafeString 'a|b') -eq 'a\|b')
ok 'newlines flattened' ((ConvertTo-LzSafeString "a`nb") -eq 'a b')
ok 'long text truncated' ((ConvertTo-LzSafeString ('x' * 500)).Length -le 300)
ok 'null becomes empty' ((ConvertTo-LzSafeString $null) -eq '')

Write-Host "`n== 8. Address collision detection ==" -ForegroundColor Cyan
$vnets = @(
    [pscustomobject]@{ Name='vnet-existing'; AddressPrefixes='10.0.0.0/16'; SubscriptionId='s1'; ResourceGroup='rg1' }
    [pscustomobject]@{ Name='vnet-other';    AddressPrefixes='192.168.0.0/16, 172.16.0.0/12'; SubscriptionId='s2'; ResourceGroup='rg2' }
)
$col = Get-LzAddressSpaceCollision -PlannedCidrs @('10.0.0.0/16','10.50.0.0/16') -ExistingVNets $vnets
ok 'detects the colliding CIDR'  (@($col).Count -eq 1)
ok 'names the conflicting VNet'  (@($col)[0].VNetName -eq 'vnet-existing')
$col2 = Get-LzAddressSpaceCollision -PlannedCidrs @('10.50.0.0/16') -ExistingVNets $vnets
ok 'no false positive'           (@($col2).Count -eq 0)
$col3 = Get-LzAddressSpaceCollision -PlannedCidrs @('172.20.0.0/16') -ExistingVNets $vnets
ok 'multi-prefix VNet matched'   (@($col3).Count -eq 1)

Write-Host "`n== 9. Readiness report renders from a synthetic run ==" -ForegroundColor Cyan
$cfg = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 25

$fakeGh = [pscustomobject]@{
    Domain='GitHub'; Owner='contoso-platform'; Repository='contoso_LZ_Deployment'
    Probes=[ordered]@{
        'Authenticated identity' = New-LzProbeResult -Name 'Authenticated identity' -Status Ok -Items @([pscustomobject]@{Login='alex'})
        'Owner account'          = New-LzProbeResult -Name 'Owner account' -Status Ok -Items @([pscustomobject]@{DetectedAsOrg=$true;Plan='free';DeclarationMatches=$true})
        'Organization runners'   = New-LzProbeResult -Name 'Organization runners' -Status Forbidden -Message 'AuthorizationFailed' -Remediation 'Grant admin:org.'
    }
    Capabilities=[pscustomobject]@{
        DetectedOwnerType='Organization'; DetectedPlan='free'; DeclaredModel='organization'
        EnvironmentsAvailable=$true; BranchProtectionAvailable=$true; Limitations=@()
    }
}
$fakeAz = [pscustomobject]@{
    Domain='Azure'; ManagementGroupRootId='mg-contoso'
    Probes=[ordered]@{
        'Management groups' = New-LzProbeResult -Name 'Management groups' -Status Ok -Items @(
            [pscustomobject]@{Name='mg-contoso';DisplayName='Contoso'}
            [pscustomobject]@{Name='mg-platform';DisplayName='Platform'}
            [pscustomobject]@{Name='mg-lz';DisplayName='Landing Zones'}
        )
        'Policy assignments' = New-LzProbeResult -Name 'Policy assignments' -Status Ok -Items (1..8 | ForEach-Object { [pscustomobject]@{Name="pa$_"} })
        'Log Analytics workspaces' = New-LzProbeResult -Name 'Log Analytics workspaces' -Status Empty
    }
    AddressCollisions=@([pscustomobject]@{PlannedCidr='10.0.0.0/16';VNetName='vnet-legacy';ExistingCidr='10.0.0.0/16';SubscriptionId='s1';ResourceGroup='rg1'})
    ExistingLandingZone=[pscustomobject]@{LikelyExisting=$true;Signals=@('A management group hierarchy already exists (3 groups).')}
}
$readiness = [pscustomobject]@{
    Checks=@(
        New-LzReadinessCheck -Id 'R01' -Category 'Identity' -Name 'Create app registrations' -Status 'Pass' -Detail 'Holds Application Administrator.'
        New-LzReadinessCheck -Id 'R08' -Category 'Networking' -Name 'Deploy networking resources' -Status 'Fail' -Detail 'Address collision.' -Remediation 'Change the hub CIDR.'
        New-LzReadinessCheck -Id 'R09' -Category 'GitHub' -Name 'GitHub access' -Status 'Warning' -Detail 'Runner policy unreadable.' -Remediation 'Grant admin:org.'
    )
    PassCount=1; WarningCount=1; FailCount=1; Ready=$false
}
$disc = [pscustomobject]@{
    GeneratedAt=(Get-Date).ToUniversalTime().ToString('o'); FactoryVersion='0.9.0'
    DurationSeconds=3.2; ConfigPath='x'; Config=$cfg
    GitHub=$fakeGh; Entra=$null; Azure=$fakeAz; Terraform=$null; Readiness=$readiness
}

$out = Join-Path $PSScriptRoot '.out/discovery-report'
$rp = New-LzReadinessReport -Discovery $disc -Path (Join-Path $out 'tenant-readiness-report.md')
$ip = Export-LzDiscoveryInventory -Discovery $disc -Path (Join-Path $out 'discovery-inventory.json')

$md = Get-Content $rp -Raw
ok 'report written'                    (Test-Path $rp)
ok 'verdict is NOT READY'              ($md -match 'NOT READY')
ok 'blocking remediation present'      ($md -match 'BLOCKING')
ok 'collision table rendered'          ($md -match 'vnet-legacy')
ok 'greenfield challenge raised'       ($md -match 'does not look empty')
ok 'forbidden probe flagged'           ($md -match 'Forbidden')
ok 'forbidden != empty in report'      ($md -match 'incomplete')
ok 'no unresolved placeholders'        ($md -notmatch '\{\{|\bundefined\b')

$inv = Get-Content $ip -Raw | ConvertFrom-Json -Depth 20
ok 'inventory is valid JSON'           ($null -ne $inv)
ok 'inventory records readOnly=true'   ($inv.readOnly -eq $true)
ok 'inventory records failCount'       ($inv.readiness.failCount -eq 1)
ok 'forbidden probe not conclusive'    ($inv.domains.GitHub.probes.'Organization runners'.conclusive -eq $false)
ok 'ok probe is conclusive'            ($inv.domains.GitHub.probes.'Authenticated identity'.conclusive -eq $true)

Write-Host "`n$script:pass passed, $script:fail failed`n" -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
exit $(if ($script:fail) { 1 } else { 0 })
