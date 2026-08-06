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
ok 'config paths flattened'            ((Get-LzTokenValue -Context $ctx -Path 'organization.companyShortName') -eq 'chg')
ok 'nested paths flattened'            ((Get-LzTokenValue -Context $ctx -Path 'azure.subscriptions.management') -eq 'aaaaaaaa-0000-0000-0000-000000000001')
ok 'arrays addressable whole'          (@(Get-LzTokenValue -Context $ctx -Path 'azure.allowedLocations').Count -eq 2)
ok 'arrays addressable positionally'   ((Get-LzTokenValue -Context $ctx -Path 'azure.allowedLocations[0]') -eq 'southcentralus')
ok 'computed.orgPrefix'                ((Get-LzTokenValue -Context $ctx -Path 'computed.orgPrefix') -eq 'chg')
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

$gNonprod = Test-LzRenderGuards -Config $cfgNonprod -FactoryVersion $fv
ok 'non-prod layer is implemented'  ($gNonprod.Violations.Id -notcontains 'G21')
ok 'valid non-prod config renders'  ($gNonprod.CanRender) (($gNonprod.Violations | ForEach-Object { $_.Id + ':' + $_.Message }) -join ' | ')

$c = Clone $cfgNonprod
$c.connectivity.hubSpoke.nonProdSpokeAddressSpaces.dev.primary = ''
ok 'G22 blocks missing non-prod CIDR' ((Test-LzRenderGuards -Config $c -FactoryVersion $fv).Violations.Id -contains 'G22')

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

Write-Host "`n== 12b. Enum constraint compatibility ==" -ForegroundColor Cyan
# The regex comparison above is blind to discrete value sets, which is how a
# schema enum offering a value `contains([...])` rejects stayed invisible.
$cnVars = Get-LzTerraformVariables -Path "$repo/factory/templates/terraform/live/platform-connectivity/variables.tf"
$fwDecl = @($cnVars | Where-Object { $_.Name -eq 'firewall_type' })[0]
ok 'extracts contains() allowed values' ((($fwDecl.ValidationAllowedValues) -join ',') -eq 'azfw,palo,fortinet') (($fwDecl.ValidationAllowedValues) -join ',')
$tierDecl = @($cnVars | Where-Object { $_.Name -eq 'azfw_tier' })[0]
ok 'extracts a second contains() list' ((($tierDecl.ValidationAllowedValues) -join ',') -eq 'Standard,Premium') (($tierDecl.ValidationAllowedValues) -join ',')
# A negated membership test over collection ELEMENTS is a deny list, not the
# set of values the variable accepts. Reading it as allowed values would invert
# its meaning, so it must not be picked up.
$ipDecl = @($cnVars | Where-Object { $_.Name -eq 'management_ip_ranges' })[0]
ok 'ignores negated element-wise contains' (@($ipDecl.ValidationAllowedValues).Count -eq 0) (@($ipDecl.ValidationAllowedValues) -join ',')

$liveSchema = Get-Content "$repo/factory/schema/lz-config.schema.json" -Raw | ConvertFrom-Json -Depth 30
ok 'reads a schema enum'          ((@(Get-LzSchemaEnum -Schema $liveSchema -Path 'connectivity.firewall.type') -join ',') -eq 'azfw,palo,fortinet')
ok 'enum absent returns null'     ($null -eq (Get-LzSchemaEnum -Schema $liveSchema -Path 'naming.orgPrefix'))
ok 'unknown path returns null'    ($null -eq (Get-LzSchemaEnum -Schema $liveSchema -Path 'connectivity.nope.nothere'))

Write-Host "`n== 12c. Schema defaults seed the render context ==" -ForegroundColor Cyan
# A schema-valid config that omits an OPTIONAL key with a declared default used
# to fail the render closed with "Unknown configuration path" — the observed
# case being backend.azurerm without useAzureAdAuth, which four templates
# reference.
$schemaFile = "$repo/factory/schema/lz-config.schema.json"
# Built from the real fixture so the context's computed.* stage has everything
# it needs; only the backend block varies.
$azurermBase = { param($extra)
    $clone = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 30
    $az = [pscustomobject]@{ resourceGroupName = 'rg'; storageAccountName = 'sa'; containerName = 'tfstate' }
    if ($extra) { $az | Add-Member -NotePropertyName useAzureAdAuth -NotePropertyValue $extra.Value }
    $clone.backend = [pscustomobject]@{ type = 'azurerm'; azurerm = $az }
    $clone
}
$ctxSeeded = New-LzRenderContext -Config (& $azurermBase $null) -SchemaPath $schemaFile
ok 'omitted optional key takes the schema default' ((Get-LzTokenValue -Context $ctxSeeded -Path 'backend.azurerm.useAzureAdAuth') -eq $true)

# Seeding must never overwrite an explicit choice — disabling Entra auth is a
# deliberate, security-relevant setting (contract #3).
$ctxExplicit = New-LzRenderContext -Config (& $azurermBase @{ Value = $false }) -SchemaPath $schemaFile
ok 'explicit config value beats the default'       ((Get-LzTokenValue -Context $ctxExplicit -Path 'backend.azurerm.useAzureAdAuth') -eq $false)

# An absent parent block must not materialise its children.
# The sample fixture is an hcp-terraform config, so it carries no azurerm
# block at all — exactly the absent-parent case.
$ctxNoAzurerm = New-LzRenderContext -Config $cfg -SchemaPath $schemaFile
$phantom = $true
try { $null = Get-LzTokenValue -Context $ctxNoAzurerm -Path 'backend.azurerm.useAzureAdAuth' } catch { $phantom = $false }
ok 'absent parent block seeds no phantom child'    (-not $phantom)

# Omitting the schema keeps the old behaviour, so callers that pass no schema
# are unaffected.
$ctxNoSchema = New-LzRenderContext -Config (& $azurermBase $null)
$unresolved = $false
try { $null = Get-LzTokenValue -Context $ctxNoSchema -Path 'backend.azurerm.useAzureAdAuth' } catch { $unresolved = $true }
ok 'no schema supplied: behaviour unchanged'       ($unresolved)

Write-Host "`n== 13. HCL formatting helpers ==" -ForegroundColor Cyan
ok 'string escaping'   ((ConvertTo-LzHclString 'a"b') -eq '"a\"b"')
ok 'null string'       ((ConvertTo-LzHclString $null) -eq '""')
ok 'empty list'        ((ConvertTo-LzHclList @()) -eq '[]')
ok 'empty map'         ((ConvertTo-LzHclMap ([pscustomobject]@{})) -eq '{}')
ok 'bool true'         ((ConvertTo-LzBoolLiteral $true) -eq 'true')
ok 'bool false'        ((ConvertTo-LzBoolLiteral $false) -eq 'false')
ok 'bool from null'    ((ConvertTo-LzBoolLiteral $null) -eq 'false')

Write-Host "`n== 14. CIDR overlap (renderer copy) ==" -ForegroundColor Cyan
ok 'overlap detected'  (Test-LzRendererCidrOverlap -CidrA '10.0.0.0/16' -CidrB '10.0.2.0/24')
ok 'disjoint'          (-not (Test-LzRendererCidrOverlap -CidrA '10.0.0.0/16' -CidrB '10.2.0.0/16'))
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
ok 'identity matrix per env'       (($idm | Select-String -Pattern 'sp-chg-.*-apply' -AllMatches).Matches.Count -eq $envCount)
# Scope to actual emitted subject rows. The document also contains prose warning
# against wildcard subjects, which must not be mistaken for one.
$subjectRows = @($idm -split "`n" | Where-Object { $_ -match '^\| \w+ \| `sp-' })
ok 'subject rows were emitted'     ($subjectRows.Count -eq ($envCount * 2)) $subjectRows.Count
ok 'no wildcard subjects emitted'  (@($subjectRows | Where-Object { $_ -match '\*' }).Count -eq 0)

$wf = Get-Content (Join-Path $out '.github/workflows/terraform-plan.yml') -Raw
ok 'workflow GHA exprs preserved'  ($wf -match '\$\{\{ matrix\.layer \}\}')
ok 'workflow permissions locked'   ($wf -match 'permissions: \{\}')

$nonprodOut = Join-Path $PSScriptRoot '.out/render-nonprod-out'
if (Test-Path $nonprodOut) { Remove-Item $nonprodOut -Recurse -Force }
$nonprodResult = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/nonprod-config.json" -OutputDirectory $nonprodOut -Quiet
ok 'non-prod layer emitted'        ($nonprodResult.Layers -contains 'workloads-nonprod')
ok 'non-prod main rendered'        (Test-Path (Join-Path $nonprodOut 'terraform/live/workloads-nonprod/main.tf'))
$nonprodTfvars = Get-Content (Join-Path $nonprodOut 'terraform/live/workloads-nonprod/terraform.auto.tfvars') -Raw
ok 'dev primary CIDR rendered'     ($nonprodTfvars -match '10\.3\.0\.0/16')
ok 'dev DR CIDR rendered'          ($nonprodTfvars -match '10\.12\.0\.0/16')

# Refuses to overwrite without -Force.
ok 'refuses non-empty output'      (throws { Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/sample-config.json" -OutputDirectory $out -Quiet })
ok 'overwrites with -Force'        (-not (throws { Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/sample-config.json" -OutputDirectory $out -Force -Quiet }))

Write-Host "`n== 15b. azurerm backend render path ==" -ForegroundColor Cyan
# Both original fixtures use hcp-terraform, so the azurerm form of the
# connectivity remote-state read and the state_* tfvars emission were never
# exercised by CI. The fixture differs from sample-config.json ONLY in its
# backend block, so a diff between the two shows exactly this surface.
#
# It also omits the optional useAzureAdAuth key on purpose: it carries a schema
# default of true, and its absence used to fail the render closed with
# "Unknown configuration path".
$azOut = Join-Path $PSScriptRoot '.out/render-azurerm-out'
if (Test-Path $azOut) { Remove-Item $azOut -Recurse -Force }
$azRes = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/azurerm-config.json" -OutputDirectory $azOut -Quiet
ok 'azurerm config renders'        ($azRes.Emitted.Count -ge 11) $azRes.Emitted.Count
ok 'no tokens left in output'      (@(Get-ChildItem $azOut -Recurse -File | Where-Object { (Get-Content $_.FullName -Raw) -match '\{\{FACTORY' }).Count -eq 0)

$azBackend = Get-Content (Join-Path $azOut 'terraform/live/global/backend.tf') -Raw
ok 'backend.tf selects azurerm'    ($azBackend -match 'backend\s+"azurerm"')
ok 'backend.tf carries the account' ($azBackend -match 'stchgtfstateabcd')
ok 'backend.tf forces AAD auth'    ($azBackend -match 'use_azuread_auth\s*=\s*true')

# The connectivity layer reads platform-management state remotely. Under
# azurerm that read must take the azurerm branch AND set use_azuread_auth,
# because the state account disables shared keys (contract #3) and the read
# would otherwise 403 at init.
$azConn = Get-Content (Join-Path $azOut 'terraform/live/platform-connectivity/main.tf') -Raw
ok 'remote state uses azurerm'     ($azConn -match 'backend\s*=\s*"azurerm"')
ok 'remote state is not hcp'       ($azConn -notmatch 'backend\s*=\s*"remote"')
ok 'remote state sets AAD auth'    ($azConn -match 'use_azuread_auth\s*=\s*true')

# state_* tfvars are what feed those reads; emitting the backend block without
# them renders a config that cannot init.
$azTfvars = Get-ChildItem (Join-Path $azOut 'terraform/live') -Recurse -Filter '*.auto.tfvars' |
    ForEach-Object { Get-Content $_.FullName -Raw }
$azTfvarsText = ($azTfvars -join "`n")
ok 'state_resource_group_name set' ($azTfvarsText -match 'state_resource_group_name\s*=\s*"rg-tfstate-scus-prod-01"')
ok 'state_storage_account_name set' ($azTfvarsText -match 'state_storage_account_name\s*=\s*"stchgtfstateabcd"')
ok 'state_container_name set'      ($azTfvarsText -match 'state_container_name\s*=\s*"tfstate"')

# Converse: the hcp fixture must NOT emit the azurerm surface, or the branch
# is not actually conditional.
$hcpConn = Get-Content (Join-Path $out 'terraform/live/platform-connectivity/main.tf') -Raw
ok 'hcp render omits azurerm read' ($hcpConn -notmatch 'backend\s*=\s*"azurerm"')

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
    'policy-diff-guardrails.yml',
    'azure-auth-test.yml'
)
foreach ($name in $expectedWorkflows) {
    ok "workflow emitted: $name" (Test-Path (Join-Path $workflowRoot $name))
}

$workflowText = @{}
foreach ($name in $expectedWorkflows) {
    $workflowText[$name] = Get-Content (Join-Path $workflowRoot $name) -Raw
    ok "$name has locked root permissions" ($workflowText[$name] -match '(?m)^permissions: \{\}$')
    ok "$name excludes pull_request_target" ($workflowText[$name] -notmatch 'pull_request_target')
    ok "$name has no unresolved factory tokens" ($workflowText[$name] -notmatch '(?<!\$)\{\{')
}

$externalUses = [regex]::Matches(
    (($workflowText.Values -join "`n")),
    '(?m)^\s*uses:\s*(?!\./|docker://)([^@\s]+)@([^\s#]+)'
)
ok 'all external actions use full SHA pins' (
    @($externalUses | Where-Object { $_.Groups[2].Value -notmatch '^[0-9a-f]{40}$' }).Count -eq 0
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

Write-Host "`n== 18. Stage 8 generated documentation corpus ==" -ForegroundColor Cyan
$expectedDocs = @(
    'operating-model.md',
    'governance.md',
    'threat-model.md',
    'observability.md',
    'finops.md',
    'state-management.md',
    'disaster-recovery.md',
    'upgrade-guide.md',
    'phase-model.md'
)
$docsRoot = Join-Path $out 'docs'
$docText = @{}
foreach ($name in $expectedDocs) {
    $path = Join-Path $docsRoot $name
    ok "documentation emitted: $name" (Test-Path $path)
    if (Test-Path $path) {
        $docText[$name] = Get-Content $path -Raw
        ok "$name has no unresolved factory tokens" ($docText[$name] -notmatch '\{\{FACTORY')
        ok "$name identifies generated provenance" (
            $docText[$name] -match 'GENERATED FILE' -and
            $docText[$name] -match [regex]::Escape($fv.factoryVersion)
        )
    }
}

ok 'operating model names platform team' (
    $docText['operating-model.md'] -match 'Cloud Platform'
)
ok 'governance renders allowed locations' (
    $docText['governance.md'] -match 'southcentralus' -and
    $docText['governance.md'] -match 'northcentralus'
)
ok 'threat model renders exact PR subject' (
    $docText['threat-model.md'] -match 'repo:contoso-platform/contoso_LZ_Deployment:pull_request'
)
ok 'observability renders configured retention' (
    $docText['observability.md'] -match '90 days'
)
ok 'finops renders accountable owner' (
    $docText['finops.md'] -match 'Jordan' -and
    $docText['finops.md'] -match 'CC-1'
)
ok 'state guide renders HCP workspace contract' (
    $docText['state-management.md'] -match 'HCP organization' -and
    $docText['state-management.md'] -match 'contoso'
)
ok 'DR guide renders both regions' (
    $docText['disaster-recovery.md'] -match 'southcentralus' -and
    $docText['disaster-recovery.md'] -match 'northcentralus'
)
ok 'upgrade guide renders schema contract' (
    $docText['upgrade-guide.md'] -match 'schema 2\.0\.0'
)
ok 'phase model renders active layers' (
    $docText['phase-model.md'] -match 'platform-connectivity' -and
    $docText['phase-model.md'] -match 'workloads-prod'
)

Write-Host "`n== 19. Stage 9 bootstrap integration ==" -ForegroundColor Cyan
$checklistPath = Join-Path $out 'USER-CHECKLIST.md'
ok 'user checklist emitted' (Test-Path $checklistPath)
if (Test-Path $checklistPath) {
    $checklist = Get-Content $checklistPath -Raw
    ok 'user checklist has no unresolved factory tokens' ($checklist -notmatch '\{\{FACTORY')
    ok 'user checklist documents plan-only default' ($checklist -match 'plan-only by default')
    ok 'user checklist documents secure TFE token' ($checklist -match 'TFE_TOKEN')
    ok 'user checklist requires live PR token exchange' ($checklist -match 'pull_request.*token exchange')
}
ok 'plan workflow selects per-layer client IDs' (
    $workflowText['terraform-plan.yml'] -match 'fromJSON\(vars\.AZURE_PLAN_CLIENT_IDS\)\[matrix\.layer\]'
)
ok 'plan workflow selects per-layer subscriptions' (
    $workflowText['terraform-plan.yml'] -match 'fromJSON\(vars\.AZURE_SUBSCRIPTION_IDS\)\[matrix\.layer\]'
)

Write-Host "`n== 20. Stage 10 scaffold integration ==" -ForegroundColor Cyan
$scaffoldEntry = Get-Content (Join-Path $repo 'scaffold-copy.ps1') -Raw
$scaffoldShell = Get-Content (Join-Path $repo 'scaffold-copy.sh') -Raw
$scaffoldModule = Get-Content (Join-Path $repo 'factory/scaffold/LZFactory.Scaffold.psm1') -Raw
ok 'scaffold entry is emitted at factory root' (Test-Path (Join-Path $repo 'scaffold-copy.ps1'))
ok 'scaffold defaults to plan-only' ($scaffoldEntry -match 'LZ_SCAFFOLD_APPLY')
ok 'scaffold shell is strict' ($scaffoldShell -match 'set -euo pipefail')
ok 'scaffold verifies exact manifest inventory' ($scaffoldModule -match 'Rendered inventory mismatch')
ok 'scaffold emits plan and audit evidence' (
    $scaffoldModule -match 'scaffold-plan\.json' -and
    $scaffoldModule -match 'scaffold-audit\.json'
)
ok 'generated checklist carries scaffold activities' (
    $checklist -match 'LZ_SCAFFOLD_APPLY' -and
    $checklist -match 'LZ_SCAFFOLD_FORCE'
)

Write-Host "`n== 21. Stage 11 brownfield import integration ==" -ForegroundColor Cyan
$importEntry = Get-Content (Join-Path $repo 'brownfield-import.ps1') -Raw
$importShell = Get-Content (Join-Path $repo 'brownfield-import.sh') -Raw
$importModule = Get-Content (Join-Path $repo 'factory/import/LZFactory.Import.psm1') -Raw
$importSchema = Get-Content (Join-Path $repo 'factory/import/brownfield-classifications.schema.json') -Raw
ok 'import entry defaults to plan-only' ($importEntry -match 'LZ_IMPORT_APPLY')
ok 'import shell is strict' ($importShell -match 'set -euo pipefail')
ok 'classification schema pins discovery inventory' ($importSchema -match 'inventorySha256')
ok 'inconclusive discovery fails closed' ($importModule -match 'Inaccessible inventory cannot be classified as empty')
ok 'import generator never executes Terraform' (
    $importModule -match 'executesTerraformImport\s*=\s*\$false' -and
    $importModule -notmatch '& terraform'
)
ok 'factory checklist carries Stage 11 activities' (
    (Get-Content (Join-Path $repo 'USER-CHECKLIST.md') -Raw) -match 'LZ_IMPORT_ALLOW_STALE'
)

Write-Host "`n== 22. Stage 12 Factory CI integration ==" -ForegroundColor Cyan
$factoryCiWorkflow = Get-Content (Join-Path $repo '.github/workflows/factory-ci.yml') -Raw
$factoryCiRunner = Get-Content (Join-Path $repo 'factory/ci/Invoke-FactoryCI.ps1') -Raw
ok 'Factory CI workflow exists' (Test-Path (Join-Path $repo '.github/workflows/factory-ci.yml'))
ok 'Factory CI is credential-free' ($factoryCiWorkflow -notmatch 'azure/login|id-token:\s*write|TFE_TOKEN')
ok 'Factory CI emits evidence' (
    $factoryCiRunner -match 'factory-ci-report\.json' -and
    $factoryCiWorkflow -match 'upload-artifact@[0-9a-f]{40}'
)
ok 'Factory CI includes schema drift' ($factoryCiRunner -match 'Test-LzSchemaDrift')
ok 'Factory CI includes Terraform validation' ($factoryCiRunner -match "terraform @\('validate'")

Write-Host "`n== 23. Guard chain on a sparse config (schema-valid, optional blocks absent) ==" -ForegroundColor Cyan
# Contract: any configuration that passes G00 schema validation must flow
# through the whole guard chain producing structured PASS/VIOLATION/ADVISORY
# results — never a StrictMode property exception. Seeded from the Stage 13
# render exercise, where a hand-authored config with `security: {}` crashed
# G02 with a raw "property 'sentinel' cannot be found" error before any guard
# result was produced.
$sparse = Clone $cfg
$sparse.security = [pscustomobject]@{}     # empty block: the original G02/G03 crasher
$sparse.governance = [pscustomobject]@{    # policyAsCodeEngines / dataResidencyRegions / requiredTags absent
    policyBaseline = [pscustomobject]@{ enforcementMode = 'audit' }
}
$sparse.github = [pscustomobject]@{        # useSelfHostedRunners / branchProtection / defaultBranch absent
    ownershipModel = $cfg.github.ownershipModel
    ownerName = $cfg.github.ownerName
    repositoryName = $cfg.github.repositoryName
    visibility = 'private'
}
$sparse.connectivity = [pscustomobject]@{ model = 'hub-spoke' }   # hubSpoke absent entirely
$sparse.environments = [pscustomobject]@{  # approvals absent; dev selected with no workloadNonProd
    platform = @($cfg.environments.platform)
    application = @('dev', 'prod')
    promotionPath = @('dev', 'prod')
}
$sparse.naming = [pscustomobject]@{ standard = 'caf' }            # defaultTags / patterns absent
$sparse.azure = [pscustomobject]@{         # allowedLocations / drRegion absent
    tenantId = $cfg.azure.tenantId
    primaryRegion = $cfg.azure.primaryRegion
    primaryRegionCode = $cfg.azure.primaryRegionCode
    subscriptions = [pscustomobject]@{
        management = $cfg.azure.subscriptions.management
        connectivity = $cfg.azure.subscriptions.connectivity
        workloadProd = $cfg.azure.subscriptions.workloadProd
    }
    managementGroups = $cfg.azure.managementGroups
}
# The schema conditionally requires backend.azurerm with both names when
# type is azurerm, so a G00-valid config cannot omit them (G18 exists for
# hand-edited configs only). Placeholder values, obviously fictional.
$sparse.backend = [pscustomobject]@{
    type = 'azurerm'
    azurerm = [pscustomobject]@{ resourceGroupName = 'rg-tfstate-test-01'; storageAccountName = 'sttfstatetest01' }
}
$sparse.PSObject.Properties.Remove('identity')                    # whole optional block absent
$sparse.PSObject.Properties.Remove('observability')               # whole optional block absent

ok 'sparse config passes G00 schema validation' (
    Test-Json -Json ($sparse | ConvertTo-Json -Depth 30) -SchemaFile "$repo/factory/schema/lz-config.schema.json" -ErrorAction SilentlyContinue
)
$sparseError = errmsg { Test-LzRenderGuards -Config $sparse -FactoryVersion $fv }
ok -name 'guard chain completes without exception' -cond ($sparseError -eq '') -extra $sparseError
if ($sparseError -eq '') {
    $gSparse = Test-LzRenderGuards -Config $sparse -FactoryVersion $fv
    ok 'guard result is structured' (
        @('Violations', 'BlockCount', 'WarnCount', 'CanRender') |
            ForEach-Object { $gSparse.PSObject.Properties.Name -contains $_ } |
            Where-Object { -not $_ } | Measure-Object |
            Select-Object -ExpandProperty Count | ForEach-Object { $_ -eq 0 }
    )
    ok 'every violation carries Id and Severity' (
        @($gSparse.Violations | Where-Object { -not $_.Id -or $_.Severity -notin @('Block', 'Warn') }).Count -eq 0
    )
    ok -name 'sparse gaps surface as violations, not crashes' -cond (
        $gSparse.Violations.Id -contains 'G22'         # dev selected, workloadNonProd/hubSpoke absent -> structured block
    ) -extra (($gSparse.Violations | ForEach-Object { $_.Id }) -join ', ')
    ok 'absent approvals produce the G14 advisory' ($gSparse.Violations.Id -contains 'G14')
    ok -name 'absent optional features stay silent' -cond (
        $gSparse.Violations.Id -notcontains 'G02' -and  # security.sentinel absent = feature off
        $gSparse.Violations.Id -notcontains 'G05' -and  # useSelfHostedRunners absent = GitHub-hosted
        $gSparse.Violations.Id -notcontains 'G11' -and  # identity block absent = no identity layer
        $gSparse.Violations.Id -notcontains 'G19'       # policyAsCodeEngines absent = no sentinel engine
    ) -extra (($gSparse.Violations | ForEach-Object { $_.Id }) -join ', ')
}
else {
    # Keep the counts aligned with the assertions above when the chain crashed.
    foreach ($skippedAssertion in @(
        'guard result is structured',
        'every violation carries Id and Severity',
        'sparse gaps surface as violations, not crashes',
        'absent approvals produce the G14 advisory',
        'absent optional features stay silent'
    )) {
        ok -name $skippedAssertion -cond $false -extra 'guard chain threw; see previous failure'
    }
}

Write-Host "`n$script:pass passed, $script:fail failed`n" -ForegroundColor $(if($script:fail){'Red'}else{'Green'})
exit $(if ($script:fail) { 1 } else { 0 })
