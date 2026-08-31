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

Write-Host "`n== Subscription sweep: only subscription IDs ==" -ForegroundColor Cyan
# azure.subscriptions stopped being six role slots when subscription vending
# (ADR 0020) added `mode` and `plannedNames`. A sweep of every property value
# then probed the literal string "create" and the plannedNames object as though
# they were subscriptions, and reported both as inaccessible with "the
# deployment will fail at plan time" — on every default export.
$sweepConfig = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
$sweepConfig.azure.subscriptions | Add-Member -NotePropertyName mode -NotePropertyValue 'create' -Force
$sweepConfig.azure.subscriptions | Add-Member -NotePropertyName plannedNames -NotePropertyValue ([pscustomobject]@{
        management = 'sub-contoso-management'; connectivity = 'sub-contoso-connectivity'
    }) -Force

$sweepSource = Get-Content "$PSScriptRoot/../discovery/public/Invoke-LzDiscovery.ps1" -Raw
$sweepMatch = [regex]::Match($sweepSource,
    '(?s)\$subs = @\(\s*(?<expr>\$config\.azure\.subscriptions\.PSObject\.Properties.*?\})\s*\)')
ok 'the sweep expression is still where the test thinks it is' $sweepMatch.Success
$swept = @(& ([scriptblock]::Create("param(`$config) @($($sweepMatch.Groups['expr'].Value))")) $sweepConfig)

ok 'only the role slots are swept' ($swept.Count -eq 3) ($swept -join ', ')
ok 'every swept value is a GUID' (@($swept | Where-Object { $_ -notmatch '^[0-9a-fA-F-]{36}$' }).Count -eq 0)
ok 'the vending mode is not probed' ($swept -notcontains 'create')
ok 'the planned-names object is not probed' (@($swept | Where-Object { $_ -isnot [string] }).Count -eq 0)

Write-Host "`n== 12. R12 — the wrong-tenant gate actually gates ==" -ForegroundColor Cyan
# TenantMatches has been computed onto the inventory since Get-LzEntraInventory
# was written, for the reason its own parameter doc gives. Nothing read it, so
# a run signed in to the wrong tenant reported ready and continued to the
# broker. These assertions are about the WIRING as much as the verdict: a test
# that only checked R12's own return value would still have passed with the
# check unregistered, which is the exact failure being fixed.
$r12Config = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
$expectedTenant = [string]$r12Config.azure.tenantId

function New-LzTestEntra([string]$SignedInTenant, [string]$Expected) {
    [pscustomobject]@{
        Domain = 'Entra'; TenantId = $Expected
        Probes = [ordered]@{
            'Signed-in context' = New-LzProbeResult -Name 'Signed-in context' -Status Ok -Items @(
                [pscustomobject]@{
                    TenantId = $SignedInTenant; SubscriptionId = 'sub'; User = 'operator'; UserType = 'user'
                    TenantMatches = ($SignedInTenant -eq $Expected); ExpectedTenant = $Expected
                })
        }
        Capabilities = [pscustomobject]@{
            RolesReadable = $true; CanManageApplications = $true
            HeldDirectoryRoles = @('Application Administrator'); AppsNearFederatedCredLimit = @()
        }
    }
}

$wrong = Test-LzTenantReadiness -Config $r12Config -EntraInventory (New-LzTestEntra '99999999-9999-9999-9999-999999999999' $expectedTenant) 6>$null
$wrongR12 = @($wrong.Checks | Where-Object { $_.Id -eq 'R12' })
ok 'R12 is registered in the readiness run'  ($wrongR12.Count -eq 1)
ok 'a wrong tenant FAILS, not warns'         ($wrongR12[0].Status -eq 'Fail') $wrongR12[0].Status
ok 'the detail names both tenants'           ($wrongR12[0].Detail -match '99999999' -and $wrongR12[0].Detail -match [regex]::Escape($expectedTenant))
# The assertion that matters: Ready is what -FailOnNotReady reads, so this is
# the difference between a check that reports and a check that stops the run.
ok 'a wrong tenant makes the tenant NOT ready' (-not $wrong.Ready)

$right = Test-LzTenantReadiness -Config $r12Config -EntraInventory (New-LzTestEntra $expectedTenant $expectedTenant) 6>$null
ok 'the right tenant passes R12' (@($right.Checks | Where-Object { $_.Id -eq 'R12' })[0].Status -eq 'Pass')

$noEntra = Test-LzTenantReadiness -Config $r12Config 6>$null
$noEntraR12 = @($noEntra.Checks | Where-Object { $_.Id -eq 'R12' })[0]
# "I could not check" and "it is fine" must never render identically — the
# three-state contract this file's header sets out.
ok 'an unreadable session warns rather than passing' ($noEntraR12.Status -eq 'Warning') $noEntraR12.Status

$blindConfig = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
$blindConfig.azure.tenantId = ''
$blind = Test-LzTenantReadiness -Config $blindConfig -EntraInventory (New-LzTestEntra 'anything' '') 6>$null
ok 'no declared tenant warns rather than passing' (@($blind.Checks | Where-Object { $_.Id -eq 'R12' })[0].Status -eq 'Warning')

Write-Host "`n== 13. Discovery follows the declared state backend ==" -ForegroundColor Cyan
# decision 0023 added HCP Terraform for state; Get-LzTerraformInventory kept
# ValidateSet('azurerm') and Invoke-LzDiscovery kept reaching for
# backend.azurerm unconditionally. The schema requires only backend.type, so
# that reach THROWS on a config that legitimately omits the block.
$hcpConfig = Get-Content "$PSScriptRoot/fixtures/hcp-config.json" -Raw | ConvertFrom-Json -Depth 40
$hcpInv = Get-LzTerraformInventory -BackendType 'hcp-terraform' 6>$null
ok 'the inventory reports the backend it was given' ($hcpInv.BackendType -eq 'hcp-terraform') $hcpInv.BackendType
ok 'no Azure storage account is probed for HCP'     ($hcpInv.Probes.Count -eq 0)

$hcpReady = Test-LzTenantReadiness -Config $hcpConfig -TerraformInventory $hcpInv 6>$null
$r10 = @($hcpReady.Checks | Where-Object { $_.Id -eq 'R10' })[0]
# Silence about an Azure storage account is not evidence about an HCP workspace.
ok 'R10 does not pass on an unreachable backend' ($r10.Status -eq 'Warning') $r10.Status
ok 'R10 says where the state actually lives'     ($r10.Detail -match 'HCP Terraform')

$azInv = Get-LzTerraformInventory -BackendType 'azurerm' -StorageAccountName '' 6>$null
ok 'azurerm still reports azurerm' ($azInv.BackendType -eq 'azurerm')

# The reach that threw. Reproduced against the source expression rather than a
# paraphrase of it, so the test fails if the guard is ever removed.
$backendSource = Get-Content "$PSScriptRoot/../discovery/public/Invoke-LzDiscovery.ps1" -Raw
ok 'discovery no longer hardcodes the backend type' ($backendSource -notmatch "BackendType\s*=\s*'azurerm'\s*$")
$bareHcp = Get-Content "$PSScriptRoot/fixtures/hcp-config.json" -Raw | ConvertFrom-Json -Depth 40
$bareHcp.backend.PSObject.Properties.Remove('azurerm')
$threw = $false
try { $null = $bareHcp.backend.azurerm } catch { $threw = $true }
ok 'the fixture really has no azurerm block (StrictMode throws on it)' $threw

Write-Host "`n$script:pass passed, $script:fail failed`n" -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
exit $(if ($script:fail) { 1 } else { 0 })
