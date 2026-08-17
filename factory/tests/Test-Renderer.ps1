#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    Renderer test suite — generator-only model (ADR 0013).

    The corpus under test emits three root-module layers referencing Azure
    Verified Modules by pinned registry source+version. The bespoke-module
    regression sections of the pre-0.10.0 suite were retired with the corpus
    they tested; what remains covers the render context, the token engine,
    the guard chain, and full renders of both topology fixtures.
#>

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$repo/factory/renderer/LZFactory.Renderer.psd1" -Force

$script:pass = 0; $script:fail = 0
function ok($name, $cond, $extra = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name $(if($extra){"-> $extra"})" -ForegroundColor Red }
}
function throws([scriptblock]$sb) { try { & $sb | Out-Null; return $false } catch { return $true } }
function errmsg([scriptblock]$sb) { try { & $sb | Out-Null; return '' } catch { return $_.Exception.Message } }
function Clone($o) { $o | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30 }

$cfg = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 30
$ctx = New-LzRenderContext -Config $cfg
$cfgNonprod = Get-Content "$PSScriptRoot/fixtures/nonprod-config.json" -Raw | ConvertFrom-Json -Depth 30
$ctxNonprod = New-LzRenderContext -Config $cfgNonprod
$cfgVwan = Get-Content "$PSScriptRoot/fixtures/vwan-config.json" -Raw | ConvertFrom-Json -Depth 30

Write-Host "`n== 1. Render context ==" -ForegroundColor Cyan
ok 'context has resolvable paths'      ($ctx.Keys.Count -gt 100) $ctx.Keys.Count
ok 'config paths flattened'            ((Get-LzTokenValue -Context $ctx -Path 'organization.companyShortName') -eq 'chg')
ok 'nested paths flattened'            ((Get-LzTokenValue -Context $ctx -Path 'azure.subscriptions.management') -eq 'aaaaaaaa-0000-0000-0000-000000000001')
ok 'arrays addressable whole'          (@(Get-LzTokenValue -Context $ctx -Path 'azure.allowedLocations').Count -eq 2)
ok 'arrays addressable positionally'   ((Get-LzTokenValue -Context $ctx -Path 'azure.allowedLocations[0]') -eq 'southcentralus')
ok 'computed.orgPrefix'                ((Get-LzTokenValue -Context $ctx -Path 'computed.orgPrefix') -eq 'chg')
ok 'computed.hasDrRegion'              ((Get-LzTokenValue -Context $ctx -Path 'computed.hasDrRegion') -eq $true)
ok 'computed.backendIsAzurerm'         ((Get-LzTokenValue -Context $ctx -Path 'computed.backendIsAzurerm') -eq $true)
ok 'computed.topologyIsHubSpoke'       ((Get-LzTokenValue -Context $ctx -Path 'computed.topologyIsHubSpoke') -eq $true)
ok 'computed.topologyIsVwan false'     ((Get-LzTokenValue -Context $ctx -Path 'computed.topologyIsVwan') -eq $false)
$ctxVwan = New-LzRenderContext -Config $cfgVwan
ok 'vwan topology computed'            ((Get-LzTokenValue -Context $ctxVwan -Path 'computed.topologyIsVwan') -eq $true)
ok 'OIDC subject computed centrally'   ((Get-LzTokenValue -Context $ctx -Path 'computed.oidcSubjectPullRequest') -match ':pull_request$')
ok 'no wildcard in computed subjects'  (-not ((Get-LzTokenValue -Context $ctx -Path 'computed.oidcSubjectPullRequest') -like '*`**'))

Write-Host "`n== 2. Layer derivation (ADR 0013: three layers, management first) ==" -ForegroundColor Cyan
$layers = @(Get-LzActiveLayers -Config $cfg)
ok 'management first (deploy order)'   ($layers[0] -eq 'platform-management')
ok 'global second'                     ($layers[1] -eq 'global')
ok 'connectivity present'              ($layers -contains 'platform-connectivity')
ok 'exactly three layers'              ($layers.Count -eq 3) ($layers -join ',')
ok 'no workload layers'                ($layers -notcontains 'workloads-prod' -and $layers -notcontains 'workloads-nonprod')
ok 'no sandbox layer'                  ($layers -notcontains 'sandbox')

$noNet = Clone $cfg
$noNet.connectivity.model = 'none'
ok 'connectivity omitted when none'    (@(Get-LzActiveLayers -Config $noNet) -notcontains 'platform-connectivity')

Write-Host "`n== 3. Token substitution ==" -ForegroundColor Cyan
ok 'plain token quotes strings'   ((Resolve-LzTemplate -Template '{{FACTORY:organization.companyShortName}}' -Context $ctx) -eq '"chg"')
ok 'RAW token is unquoted'        ((Resolve-LzTemplate -Template '{{FACTORY-RAW:organization.companyShortName}}' -Context $ctx) -eq 'chg')
ok 'BOOL token'                   ((Resolve-LzTemplate -Template '{{FACTORY-BOOL:connectivity.bastion.enabled}}' -Context $ctx) -eq 'true')
ok 'LIST token renders HCL list'  ((Resolve-LzTemplate -Template '{{FACTORY-LIST:azure.allowedLocations}}' -Context $ctx) -eq '["southcentralus", "northcentralus"]')
ok 'NUM token unquoted'           ((Resolve-LzTemplate -Template '{{FACTORY-NUM:observability.logAnalytics.retentionDays}}' -Context $ctx) -eq '90')
ok 'MAP token renders HCL map'    ((Resolve-LzTemplate -Template '{{FACTORY-MAP:naming.defaultTags}}' -Context $ctx) -match 'owner\s+= "platform"')
ok 'JSON token'                   ((Resolve-LzTemplate -Template '{{FACTORY-JSON:azure.allowedLocations}}' -Context $ctx) -match '^\[')

Write-Host "`n== 4. Fail-closed behaviour ==" -ForegroundColor Cyan
ok 'unknown token path throws'    (throws { Resolve-LzTemplate -Template '{{FACTORY:does.not.exist}}' -Context $ctx })
$m = errmsg { Resolve-LzTemplate -Template '{{FACTORY:organization.companyShortNam}}' -Context $ctx }
ok 'unknown path suggests near-miss' ($m -match 'Did you mean')
ok 'mistyped token kind is caught' (throws { Resolve-LzTemplate -Template '{{FACTORY-LST:azure.allowedLocations}}' -Context $ctx })
ok 'stray placeholder is caught'   (throws { Resolve-LzTemplate -Template 'x {{oops}} y' -Context $ctx })
ok 'unbalanced IF throws'          (throws { Resolve-LzTemplate -Template "a`n#{{IF computed.hasDrRegion}}`nb" -Context $ctx })
ok 'ENDIF without IF throws'       (throws { Resolve-LzTemplate -Template "a`n#{{ENDIF}}" -Context $ctx })
ok 'unbalanced FOREACH throws'     (throws { Resolve-LzTemplate -Template "#{{FOREACH x IN computed.layers}}`na" -Context $ctx })
ok 'malformed FOREACH throws'      (throws { Resolve-LzTemplate -Template "#{{FOREACH bad}}`na`n#{{ENDFOREACH}}" -Context $ctx })
ok 'bad expression throws'         (throws { Resolve-LzTemplate -Template "#{{IF a b c d}}`nx`n#{{ENDIF}}" -Context $ctx })

Write-Host "`n== 5. GitHub Actions expressions survive ==" -ForegroundColor Cyan
$gha = 'run: echo ${{ matrix.layer }} ${{ github.ref }}'
ok 'GHA expressions untouched'     ((Resolve-LzTemplate -Template $gha -Context $ctx) -eq $gha)
ok 'GHA + factory token together'  ((Resolve-LzTemplate -Template 'a ${{ github.ref }} {{FACTORY-RAW:organization.companyShortName}}' -Context $ctx) -eq 'a ${{ github.ref }} chg')

Write-Host "`n== 6. Conditionals ==" -ForegroundColor Cyan
$t = "a`n#{{IF computed.hasDrRegion}}`nDR`n#{{ELSE}}`nNODR`n#{{ENDIF}}`nz"
ok 'IF true branch'                ((Resolve-LzTemplate -Template $t -Context $ctx) -match 'DR' )
ok 'IF excludes else branch'       ((Resolve-LzTemplate -Template $t -Context $ctx) -notmatch 'NODR')
$t2 = "#{{IF connectivity.model == 'virtual-wan'}}`nVWAN`n#{{ELSEIF connectivity.model == 'hub-spoke'}}`nHS`n#{{ELSE}}`nOTHER`n#{{ENDIF}}"
$r2 = Resolve-LzTemplate -Template $t2 -Context $ctx
ok 'ELSEIF selects correct branch' ($r2 -match 'HS' -and $r2 -notmatch 'VWAN' -and $r2 -notmatch 'OTHER')
ok 'equality operator'             ((Resolve-LzTemplate -Template "#{{IF backend.type == 'azurerm'}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'inequality operator'           ((Resolve-LzTemplate -Template "#{{IF connectivity.model != 'none'}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'contains operator'             ((Resolve-LzTemplate -Template "#{{IF environments.application contains 'prod'}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'negation operator'             ((Resolve-LzTemplate -Template "#{{IF !github.useSelfHostedRunners}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'conjunction'                   ((Resolve-LzTemplate -Template "#{{IF computed.hasDrRegion && computed.topologyIsHubSpoke}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'disjunction'                   ((Resolve-LzTemplate -Template "#{{IF github.useSelfHostedRunners || computed.topologyIsHubSpoke}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')

Write-Host "`n== 7. ``defined`` operator (optional keys are stripped, not empty) ==" -ForegroundColor Cyan
ok 'bare path on missing key throws' (throws { Resolve-LzTemplate -Template "#{{IF azure.subscriptions.identity}}`nX`n#{{ENDIF}}" -Context $ctx })
ok 'defined on missing key is false' ((Resolve-LzTemplate -Template "#{{IF defined azure.subscriptions.identity}}`nX`n#{{ENDIF}}" -Context $ctx) -notmatch 'X')
ok 'defined on present key is true'  ((Resolve-LzTemplate -Template "#{{IF defined azure.subscriptions.management}}`nX`n#{{ENDIF}}" -Context $ctx) -match 'X')
ok '!defined inverts'                ((Resolve-LzTemplate -Template "#{{IF !defined azure.subscriptions.identity}}`nX`n#{{ENDIF}}" -Context $ctx) -match 'X')

Write-Host "`n== 8. Tokens in skipped blocks are never evaluated ==" -ForegroundColor Cyan
$t3 = "#{{IF !computed.hasDrRegion}}`n{{FACTORY:does.not.exist}}`n#{{ENDIF}}`nsafe"
ok 'excluded block token not resolved' (-not (throws { Resolve-LzTemplate -Template $t3 -Context $ctx }))

Write-Host "`n== 9. FOREACH ==" -ForegroundColor Cyan
$loop = Resolve-LzTemplate -Template "#{{FOREACH l IN computed.layers}}`n- {{FACTORY-RAW:l}}`n#{{ENDFOREACH}}" -Context $ctx
ok 'loop emits one line per item'  (@($loop -split "`n" | Where-Object { $_ -match '^- ' }).Count -eq $layers.Count) $loop
ok 'loop variable substituted'     ($loop -match '- global')
$nested = Resolve-LzTemplate -Template "#{{FOREACH e IN environments.application}}`n#{{IF e == 'prod'}}`nPROD:{{FACTORY-RAW:e}}`n#{{ENDIF}}`n#{{ENDFOREACH}}" -Context $ctxNonprod
ok 'IF nested inside FOREACH'      ($nested -match 'PROD:prod' -and $nested -notmatch 'PROD:dev')

Write-Host "`n== 10. Render guards ==" -ForegroundColor Cyan
$fv = Get-Content "$repo/factory-version.json" -Raw | ConvertFrom-Json -Depth 15
$g = Test-LzRenderGuards -Config $cfg -FactoryVersion $fv
ok 'valid config renders'          ($g.CanRender) (($g.Violations | ForEach-Object { $_.Id + ':' + $_.Message }) -join ' | ')

$c = Clone $cfg; $c.security.sentinel.enabled = $true
$gs = Test-LzRenderGuards -Config $c -FactoryVersion $fv
ok 'G02 warns on Sentinel answer'  (@($gs.Violations | Where-Object { $_.Id -eq 'G02' -and $_.Severity -eq 'Warn' }).Count -eq 1)
ok 'G02 does not block'            ($gs.CanRender)

$c = Clone $cfg; $c.connectivity.model = 'virtual-wan'
$gv = Test-LzRenderGuards -Config $c -FactoryVersion $fv
ok 'virtual-wan renders'           ($gv.CanRender) (($gv.Violations | ForEach-Object { $_.Id }) -join ',')
ok 'G04 warns on vwan+bastion'     (@($gv.Violations | Where-Object { $_.Id -eq 'G04' }).Count -ge 1)

$c = Clone $cfg; $c.backend.type = 'hcp-terraform'
ok 'G17 blocks non-azurerm backend' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G17')

$c = Clone $cfg; $c.backend.azurerm.storageAccountName = ''
ok 'G18 blocks missing state account' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G18')

$c = Clone $cfg; $c.azure.subscriptions.management = ''
ok 'G09 blocks missing management sub' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G09')

$c = Clone $cfg; $c.connectivity.hubSpoke.drHubAddressSpace = $c.connectivity.hubSpoke.primaryHubAddressSpace
ok 'G12 blocks overlapping CIDRs'  ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G12')

$c = Clone $cfg; $c.naming.defaultTags = [pscustomobject]@{}
ok 'G06 blocks missing required tags' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G06')

Write-Host "`n== 11. Full render — hub-and-spoke fixture ==" -ForegroundColor Cyan
$out = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
$result = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/azurerm-config.json" -OutputDirectory $out -Quiet
ok 'render returns a result'       ($null -ne $result)
ok 'render-manifest written'       (Test-Path (Join-Path $out 'render-manifest.json'))

foreach ($required in @(
    '.gitignore', 'renovate.json', 'lz-config.json', 'factory-version.json',
    'README.md', 'USER-CHECKLIST.md',
    'terraform/live/platform-management/main.tf',
    'terraform/live/platform-management/backend.tf',
    'terraform/live/platform-management/backend.hcl',
    'terraform/live/global/main.tf',
    'terraform/live/global/terraform.auto.tfvars',
    'terraform/live/platform-connectivity/main.tf',
    '.github/workflows/terraform-plan.yml',
    '.github/workflows/terraform-apply.yml'
)) {
    ok "emits $required" (Test-Path (Join-Path $out $required))
}

$globalMain = Get-Content (Join-Path $out 'terraform/live/global/main.tf') -Raw
ok 'global references avm-ptn-alz by registry pin' ($globalMain -match 'source\s+=\s+"Azure/avm-ptn-alz/azurerm"' -and $globalMain -match 'version\s+=\s+"0\.21\.0"')
ok 'alz provider pins the library'   ($globalMain -match 'library_references' -and $globalMain -match '2026\.04\.2')
$mgmtMain = Get-Content (Join-Path $out 'terraform/live/platform-management/main.tf') -Raw
ok 'management references avm-ptn-alz-management' ($mgmtMain -match 'source\s+=\s+"Azure/avm-ptn-alz-management/azurerm"')
$connMain = Get-Content (Join-Path $out 'terraform/live/platform-connectivity/main.tf') -Raw
ok 'hub-spoke fixture emits hub-and-spoke module' ($connMain -match 'avm-ptn-alz-connectivity-hub-and-spoke-vnet')
ok 'hub-spoke fixture omits virtual-wan module'   ($connMain -notmatch 'avm-ptn-alz-connectivity-virtual-wan')

$vendored = @(Get-ChildItem -Path $out -Recurse -Directory | Where-Object { $_.Name -eq 'modules' })
ok 'no module source vendored'      ($vendored.Count -eq 0)
$localRefs = Select-String -Path (Join-Path $out 'terraform/live/*/main.tf') -Pattern '\.\./\.\./modules/' -SimpleMatch:$false
ok 'no local module references'     ($null -eq $localRefs)

$backendTf = Get-Content (Join-Path $out 'terraform/live/global/backend.tf') -Raw
ok 'backend block is empty'         ($backendTf -match 'backend "azurerm" \{\}')
$backendHcl = Get-Content (Join-Path $out 'terraform/live/global/backend.hcl') -Raw
ok 'backend.hcl sets use_oidc'      ($backendHcl -match 'use_oidc\s+=\s+true')
ok 'backend.hcl sets azuread auth'  ($backendHcl -match 'use_azuread_auth\s+=\s+true')
ok 'backend.hcl per-layer state key' ($backendHcl -match 'key\s+=\s+"global\.tfstate"')

$gitignore = Get-Content (Join-Path $out '.gitignore') -Raw
ok '.gitignore covers .alzlib/'     ($gitignore -match '\.alzlib/')
$stamp = Get-Content (Join-Path $out 'factory-version.json') -Raw | ConvertFrom-Json
ok 'version stamp carries factory version' ("$($stamp.factoryVersion)" -eq "$($fv.factoryVersion)")
$answerRecord = Get-Content (Join-Path $out 'lz-config.json') -Raw | ConvertFrom-Json -Depth 30
ok 'answer record round-trips'      ("$($answerRecord.schemaVersion)" -eq '2.2.0')
$renovate = Get-Content (Join-Path $out 'renovate.json') -Raw | ConvertFrom-Json -Depth 10
ok 'renovate targets terraform manager' (@($renovate.packageRules[0].matchManagers) -contains 'terraform')

$residual = Select-String -Path (Get-ChildItem $out -Recurse -File).FullName -Pattern '(?<!\$)\{\{[^}]*\}\}' -AllMatches -ErrorAction SilentlyContinue |
    Where-Object { $_.Line -notmatch '\$\{\{' }
ok 'zero residual factory tokens'   (@($residual).Count -eq 0) (@($residual | Select-Object -First 3 | ForEach-Object { $_.Path + ':' + $_.LineNumber }) -join '; ')

Write-Host "`n== 12. Full render — Virtual WAN fixture ==" -ForegroundColor Cyan
$outVwan = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
$null = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/vwan-config.json" -OutputDirectory $outVwan -Quiet
$connVwan = Get-Content (Join-Path $outVwan 'terraform/live/platform-connectivity/main.tf') -Raw
ok 'vwan fixture emits virtual-wan module' ($connVwan -match 'avm-ptn-alz-connectivity-virtual-wan' -and $connVwan -match '0\.17\.1')
ok 'vwan fixture omits hub-and-spoke'      ($connVwan -notmatch 'hub-and-spoke-vnet')

Write-Host "`n== 13. Schema drift check ==" -ForegroundColor Cyan
$drift = Test-LzSchemaDrift -SchemaPath "$repo/factory/schema/lz-config.schema.json" -MappingPath "$repo/factory/renderer/variable-map.json" -TemplateRoot "$repo/factory/templates"
ok 'wizard and corpus in sync'      ($drift.InSync) (($drift.Findings | Select-Object -First 3 | ForEach-Object { $_.Detail }) -join '; ')

Remove-Item -Recurse -Force $out, $outVwan -ErrorAction SilentlyContinue

Write-Host "`n== Results: $script:pass passed, $script:fail failed ==" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 }
