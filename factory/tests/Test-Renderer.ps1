#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo root resolved from this script's location so the suite runs from
# any checkout, on any machine, from any working directory.
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$repo/factory/renderer/LZFactory.Renderer.psd1" -Force

$script:pass = 0; $script:fail = 0
function ok($name, $cond, $extra = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name $(if($extra){"-> $extra"})" -ForegroundColor Red }
}
function throws([scriptblock]$sb) { try { & $sb | Out-Null; return $false } catch { return $true } }
function errmsg([scriptblock]$sb) { try { & $sb | Out-Null; return '' } catch { return $_.Exception.Message } }

$cfg = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 30
$ctx = New-LzRenderContext -Config $cfg

# Identical to the sample except that it also selects a non-prod application
# environment, which makes Get-LzActiveLayers select workloads-nonprod — a
# layer the template corpus has no Terraform for. Kept as its own fixture so
# the refusal is asserted rather than avoided.
$cfgNonprod = Get-Content "$PSScriptRoot/fixtures/nonprod-config.json" -Raw | ConvertFrom-Json -Depth 30
$ctxNonprod = New-LzRenderContext -Config $cfgNonprod

Write-Host "`n== 1. Render context ==" -ForegroundColor Cyan
ok 'context has resolvable paths'      ($ctx.Keys.Count -gt 100) $ctx.Keys.Count
ok 'config paths flattened'            ((Get-LzTokenValue -Context $ctx -Path 'organization.companyShortName') -eq 'contoso')
ok 'nested paths flattened'            ((Get-LzTokenValue -Context $ctx -Path 'azure.subscriptions.management') -eq 'aaaaaaaa-0000-0000-0000-000000000001')
ok 'arrays addressable whole'          (@(Get-LzTokenValue -Context $ctx -Path 'azure.allowedLocations').Count -eq 2)
ok 'arrays addressable positionally'   ((Get-LzTokenValue -Context $ctx -Path 'azure.allowedLocations[0]') -eq 'southcentralus')
ok 'computed.orgPrefix'                ((Get-LzTokenValue -Context $ctx -Path 'computed.orgPrefix') -eq 'contoso')
ok 'computed.repositorySlug'           ((Get-LzTokenValue -Context $ctx -Path 'computed.repositorySlug') -eq 'contoso-platform/contoso_LZ_Deployment')
ok 'computed.hasDrRegion'              ((Get-LzTokenValue -Context $ctx -Path 'computed.hasDrRegion') -eq $true)
ok 'computed.backendIsHcp'             ((Get-LzTokenValue -Context $ctx -Path 'computed.backendIsHcp') -eq $true)
ok 'OIDC subject computed centrally'   ((Get-LzTokenValue -Context $ctx -Path 'computed.oidcSubjectPullRequest') -eq 'repo:contoso-platform/contoso_LZ_Deployment:pull_request')
ok 'no wildcard in computed subjects'  (-not ((Get-LzTokenValue -Context $ctx -Path 'computed.oidcSubjectPullRequest') -like '*`**'))

Write-Host "`n== 2. Layer derivation (layers are never merged) ==" -ForegroundColor Cyan
$layers = @(Get-LzActiveLayers -Config $cfg)
ok 'global always present'             ($layers -contains 'global')
ok 'connectivity present'              ($layers -contains 'platform-connectivity')
ok 'workloads-prod present'            ($layers -contains 'workloads-prod')
ok 'sandbox absent without a sub'      ($layers -notcontains 'sandbox')
ok 'identity absent without a sub'     ($layers -notcontains 'platform-identity')

$noNet = $cfg | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
$noNet.connectivity.model = 'none'
ok 'connectivity omitted when none'    (@(Get-LzActiveLayers -Config $noNet) -notcontains 'platform-connectivity')

Write-Host "`n== 3. Token substitution ==" -ForegroundColor Cyan
ok 'plain token quotes strings'   ((Resolve-LzTemplate -Template '{{FACTORY:organization.companyShortName}}' -Context $ctx) -eq '"contoso"')
ok 'RAW token is unquoted'        ((Resolve-LzTemplate -Template '{{FACTORY-RAW:organization.companyShortName}}' -Context $ctx) -eq 'contoso')
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
ok 'GHA + factory token together'  ((Resolve-LzTemplate -Template 'a ${{ github.ref }} {{FACTORY-RAW:organization.companyShortName}}' -Context $ctx) -eq 'a ${{ github.ref }} contoso')

Write-Host "`n== 6. Conditionals ==" -ForegroundColor Cyan
$t = "a`n#{{IF computed.hasDrRegion}}`nDR`n#{{ELSE}}`nNODR`n#{{ENDIF}}`nz"
ok 'IF true branch'                ((Resolve-LzTemplate -Template $t -Context $ctx) -match 'DR' )
ok 'IF excludes else branch'       ((Resolve-LzTemplate -Template $t -Context $ctx) -notmatch 'NODR')
$t2 = "#{{IF connectivity.firewall.type == 'palo'}}`nPALO`n#{{ELSEIF connectivity.firewall.type == 'azfw'}}`nAZFW`n#{{ELSE}}`nOTHER`n#{{ENDIF}}"
$r2 = Resolve-LzTemplate -Template $t2 -Context $ctx
ok 'ELSEIF selects correct branch' ($r2 -match 'AZFW' -and $r2 -notmatch 'PALO' -and $r2 -notmatch 'OTHER')
ok 'equality operator'             ((Resolve-LzTemplate -Template "#{{IF backend.type == 'hcp-terraform'}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'inequality operator'           ((Resolve-LzTemplate -Template "#{{IF backend.type != 'azurerm'}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'contains operator'             ((Resolve-LzTemplate -Template "#{{IF environments.application contains 'prod'}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'negation operator'             ((Resolve-LzTemplate -Template "#{{IF !github.useSelfHostedRunners}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'conjunction'                   ((Resolve-LzTemplate -Template "#{{IF computed.hasDrRegion && computed.backendIsHcp}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')
ok 'disjunction'                   ((Resolve-LzTemplate -Template "#{{IF github.useSelfHostedRunners || computed.backendIsHcp}}`nY`n#{{ENDIF}}" -Context $ctx) -match 'Y')

Write-Host "`n== 7. `defined` operator (optional keys are stripped, not empty) ==" -ForegroundColor Cyan
ok 'bare path on missing key throws' (throws { Resolve-LzTemplate -Template "#{{IF azure.subscriptions.identity}}`nX`n#{{ENDIF}}" -Context $ctx })
ok 'defined on missing key is false' ((Resolve-LzTemplate -Template "#{{IF defined azure.subscriptions.identity}}`nX`n#{{ENDIF}}" -Context $ctx) -notmatch 'X')
ok 'defined on present key is true'  ((Resolve-LzTemplate -Template "#{{IF defined azure.subscriptions.management}}`nX`n#{{ENDIF}}" -Context $ctx) -match 'X')
ok '!defined inverts'                ((Resolve-LzTemplate -Template "#{{IF !defined azure.subscriptions.identity}}`nX`n#{{ENDIF}}" -Context $ctx) -match 'X')

Write-Host "`n== 8. Tokens in skipped blocks are never evaluated ==" -ForegroundColor Cyan
# This is why directives run before token substitution.
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

function Clone($o) { $o | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30 }

$c = Clone $cfg; $c.security.sentinel.enabled = $true
ok 'G02 blocks scaffold Sentinel'  ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G02')

$c = Clone $cfg; $c.security.keyVault.customerManagedKeys = $true
ok 'G03 blocks scaffold CMK'       ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G03')

$c = Clone $cfg; $c.connectivity.model = 'virtual-wan'
ok 'G04 blocks virtual-wan'        ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G04')

$c = Clone $cfg; $c.github.useSelfHostedRunners = $true
ok 'G05 blocks self-hosted runners' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G05')

$c = Clone $cfg; $c.naming.defaultTags = [pscustomobject]@{ owner = 'x' }
ok 'G06 blocks missing tag default' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G06')

$c = Clone $cfg; $c.azure.allowedLocations = @('westeurope')
ok 'G07 blocks region not allowed'  ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G07')

$c = Clone $cfg; $c.connectivity.hubSpoke.primarySpokeAddressSpace = '10.0.0.0/16'
ok 'G12 blocks overlapping CIDRs'   ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G12')

$c = Clone $cfg; $c.schemaVersion = '9.9.9'
ok 'G01 blocks schema mismatch'     ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G01')

$c = Clone $cfg; $c.naming.standard = 'custom'
$c.naming | Add-Member -NotePropertyName resourceGroupPattern -NotePropertyValue 'rg-{scope}-{bogus}' -Force
$c.naming | Add-Member -NotePropertyName resourcePattern -NotePropertyValue '{type}-{workload}' -Force
ok 'G16 blocks unknown name token'  ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G16')

$c = Clone $cfg; $c.governance.policyAsCodeEngines = @('sentinel'); $c.backend.type = 'azurerm'
ok 'G19 blocks Sentinel w/o HCP'    ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G19')

# A layer with no Terraform must be refused, not emitted as a directory holding
# only backend.tf — which initialises cleanly and plans zero resources, and so
# reads as "nothing to do" rather than "not implemented".
$gNonprod = Test-LzRenderGuards -Config $cfgNonprod -FactoryVersion $fv
ok 'G21 blocks unimplemented layer' ($gNonprod.Violations.Id -contains 'G21')
ok 'G21 names the missing layer'    ((($gNonprod.Violations | Where-Object { $_.Id -eq 'G21' }).Message) -match 'workloads-nonprod')
ok 'G21 refuses the render'         (throws { Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/nonprod-config.json" -OutputDirectory (Join-Path $PSScriptRoot '.out/g21') -Quiet })

Write-Host "`n== 11. Schema drift detection ==" -ForegroundColor Cyan
$d = Test-LzSchemaDrift -SchemaPath "$repo/factory/schema/lz-config.schema.json" `
                        -MappingPath "$repo/factory/renderer/variable-map.json" `
                        -TemplateRoot "$repo/factory/templates"
ok 'corpus is currently in sync'  ($d.InSync) (($d.Findings | ForEach-Object { $_.Detail }) -join ' | ')

$vars = Get-LzTerraformVariables -Path "$repo/factory/templates/terraform/live/global/variables.tf"
ok 'parses all variables'         (@($vars).Count -eq 8) @($vars).Count
ok 'detects HasDefault'           ((@($vars | Where-Object { $_.Name -eq 'org_prefix' })[0].HasDefault) -eq $false)
ok 'extracts validation regex'    ((@($vars | Where-Object { $_.Name -eq 'org_prefix' })[0].ValidationRegex) -eq '^[a-z0-9]{2,10}$')

Write-Host "`n== 12. Constraint counterexamples ==" -ForegroundColor Cyan
ok 'identical patterns: no finding' ($null -eq (Get-LzConstraintCounterexample -SchemaPattern '^[a-z]{2,4}$' -TerraformPattern '^[a-z]{2,4}$'))
$ce = Get-LzConstraintCounterexample -SchemaPattern '^[a-z0-9]{2,10}$' -TerraformPattern '^[a-z]{2,4}$'
ok 'narrower Terraform regex caught' ($null -ne $ce)
ok 'counterexample is real'          ($ce -and [regex]::IsMatch($ce,'^[a-z0-9]{2,10}$') -and -not [regex]::IsMatch($ce,'^[a-z]{2,4}$')) $ce
ok 'wider Terraform regex: no finding' ($null -eq (Get-LzConstraintCounterexample -SchemaPattern '^[a-z]{2,4}$' -TerraformPattern '^[a-z0-9]{2,10}$'))

Write-Host "`n== 13. HCL formatting helpers ==" -ForegroundColor Cyan
ok 'string escaping'   ((ConvertTo-LzHclString 'a"b') -eq '"a\"b"')
ok 'null string'       ((ConvertTo-LzHclString $null) -eq '""')
ok 'empty list'        ((ConvertTo-LzHclList @()) -eq '[]')
ok 'empty map'         ((ConvertTo-LzHclMap ([pscustomobject]@{})) -eq '{}')
ok 'bool true'         ((ConvertTo-LzBoolLiteral $true) -eq 'true')
ok 'bool false'        ((ConvertTo-LzBoolLiteral $false) -eq 'false')
ok 'bool from null'    ((ConvertTo-LzBoolLiteral $null) -eq 'false')

Write-Host "`n== 14. CIDR overlap (renderer copy) ==" -ForegroundColor Cyan
ok 'overlap detected'  (Test-LzRendererCidrOverlap -CidrA '10.0.0.0/16' -CidrB '10.0.1.0/24')
ok 'disjoint'          (-not (Test-LzRendererCidrOverlap -CidrA '10.0.0.0/16' -CidrB '10.1.0.0/16'))
ok 'malformed safe'    (-not (Test-LzRendererCidrOverlap -CidrA 'nope' -CidrB '10.0.0.0/16'))

Write-Host "`n== 15. End-to-end render ==" -ForegroundColor Cyan
$out = Join-Path $PSScriptRoot '.out/render-test-out'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$res = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/sample-config.json" -OutputDirectory $out -Quiet
ok 'files emitted'                 ($res.Emitted.Count -ge 11) $res.Emitted.Count
ok 'render manifest written'       (Test-Path (Join-Path $out 'render-manifest.json'))
ok 'one backend.tf per layer'      (@(Get-ChildItem -Path (Join-Path $out 'terraform/live') -Recurse -Filter 'backend.tf').Count -eq $layers.Count)
ok 'no factory tokens in output'   (@(Get-ChildItem $out -Recurse -File | Where-Object { (Get-Content $_.FullName -Raw) -match '\{\{FACTORY' }).Count -eq 0)

$readme = Get-Content (Join-Path $out 'README.md') -Raw
ok 'README has company name'       ($readme -match 'Contoso Health Group')
ok 'README lists layers'           ($readme -match 'terraform/live/global')
ok 'brownfield section omitted'    ($readme -notmatch '## Brownfield')

$idm = Get-Content (Join-Path $out 'docs/identity-trust-matrix.md') -Raw
# Derived from the fixture rather than hard-coded, so changing which
# environments the fixture selects does not require editing an unrelated count.
$envCount = @($ctx.Tokens['computed.allEnvironments']).Count
ok 'identity matrix per env'       (($idm | Select-String -Pattern 'sp-contoso-.*-apply' -AllMatches).Matches.Count -eq $envCount)
# Scope to actual emitted subject rows. The document also contains prose warning
# against wildcard subjects, which must not be mistaken for one.
$subjectRows = @($idm -split "`n" | Where-Object { $_ -match '^\| \w+ \| `sp-' })
ok 'subject rows were emitted'     ($subjectRows.Count -eq ($envCount * 2)) $subjectRows.Count
ok 'no wildcard subjects emitted'  (@($subjectRows | Where-Object { $_ -match '\*' }).Count -eq 0)

$wf = Get-Content (Join-Path $out '.github/workflows/terraform-plan.yml') -Raw
ok 'workflow GHA exprs preserved'  ($wf -match '\$\{\{ matrix\.layer \}\}')
ok 'workflow permissions locked'   ($wf -match 'permissions: \{\}')

# Refuses to overwrite without -Force.
ok 'refuses non-empty output'      (throws { Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/sample-config.json" -OutputDirectory $out -Quiet })
ok 'overwrites with -Force'        (-not (throws { Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/sample-config.json" -OutputDirectory $out -Force -Quiet }))

Write-Host "`n== 16. Guard violation stops the render ==" -ForegroundColor Cyan
$badCfgPath = Join-Path $PSScriptRoot '.out/bad-config.json'
$bad = Clone $cfg; $bad.connectivity.model = 'virtual-wan'
$bad | ConvertTo-Json -Depth 30 | Set-Content $badCfgPath -Encoding utf8
$badOut = Join-Path $PSScriptRoot '.out/render-bad-out'
if (Test-Path $badOut) { Remove-Item $badOut -Recurse -Force }
ok 'blocked config throws'         (throws { Invoke-LzRender -ConfigPath $badCfgPath -OutputDirectory $badOut -Quiet })
ok 'nothing written when blocked'  (-not (Test-Path (Join-Path $badOut 'README.md')))

Write-Host "`n== 17. Stage 7 generated workflow corpus ==" -ForegroundColor Cyan
$workflowRoot = Join-Path $out '.github/workflows'
$expectedWorkflows = @(
    'terraform-plan.yml',
    'terraform-fmt-validate.yml',
    'terraform-apply.yml',
    'action-pinning-policy.yml',
    'security-scan.yml',
    'terraform-policy-checks.yml',
    'azure-auth-test.yml'
)
foreach ($name in $expectedWorkflows) {
    ok "workflow emitted: $name" (Test-Path (Join-Path $workflowRoot $name))
}

$workflowText = @{}
foreach ($name in $expectedWorkflows) {
    $workflowText[$name] = Get-Content (Join-Path $workflowRoot $name) -Raw
    ok "$name has locked root permissions" ($workflowText[$name] -match '(?m)^permissions: \{\} -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
exit $(if ($script:fail) { 1 } else { 0 })
)
    ok "$name excludes pull_request_target" ($workflowText[$name] -notmatch 'pull_request_target')
    ok "$name has no unresolved factory tokens" ($workflowText[$name] -notmatch '(?<!\$)\{\{')
}

$externalUses = [regex]::Matches(
    (($workflowText.Values -join "`n")),
    '(?m)^\s*uses:\s*(?!\./|docker://)([^@\s]+)@([^\s#]+)'
)
ok 'all external actions use full SHA pins' (
    @($externalUses | Where-Object { $_.Groups[2].Value -notmatch '^[0-9a-f]{40} -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
exit $(if ($script:fail) { 1 } else { 0 })
 }).Count -eq 0
)

ok 'forks receive credential-free validation' (
    $workflowText['terraform-fmt-validate.yml'] -match 'pull_request' -and
    $workflowText['terraform-fmt-validate.yml'] -notmatch 'id-token:\s*write'
)
ok 'cloud plan skips forked pull requests' (
    $workflowText['terraform-plan.yml'] -match 'head\.repo\.full_name == github\.repository'
)
ok 'apply binds protected environment' (
    $workflowText['terraform-apply.yml'] -match '(?m)^\s*environment:\s*\$\{\{ inputs\.environment \}\}'
)
ok 'apply uses apply identity variable' (
    $workflowText['terraform-apply.yml'] -match 'AZURE_APPLY_CLIENT_ID'
)
ok 'apply does not contain plan identity' (
    $workflowText['terraform-apply.yml'] -notmatch 'AZURE_PLAN_CLIENT_ID'
)
ok 'apply refuses destructive plan' (
    $workflowText['terraform-apply.yml'] -match 'Refuse destructive apply'
)

Write-Host "`n$script:pass passed, $script:fail failed`n" -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
exit $(if ($script:fail) { 1 } else { 0 })
