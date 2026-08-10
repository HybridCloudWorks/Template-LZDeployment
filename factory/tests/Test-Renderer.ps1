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

# End-to-end: the unit assertions above prove the two extractors work in
# isolation, but the azfw `Basic` defect (TODO 1.3) reached main because
# nothing seeded an actual enum/contains() disagreement THROUGH
# Test-LzSchemaDrift and asserted the check fails. This section replays that
# defect shape against a seeded corpus: the schema enum still offers `Basic`
# while the Terraform validation accepts only Standard|Premium.
Write-Host "`n== 12b-2. Seeded enum/contains() mismatch fails the drift check ==" -ForegroundColor Cyan
$seedRoot = Join-Path $PSScriptRoot '.out/drift-enum-seed'
if (Test-Path $seedRoot) { Remove-Item $seedRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $seedRoot 'templates/terraform/live/platform-connectivity') -Force | Out-Null
@'
{
  "properties": {
    "connectivity": {
      "properties": {
        "firewall": {
          "properties": {
            "tier": { "type": "string", "enum": ["Standard", "Premium", "Basic"] }
          }
        }
      }
    }
  }
}
'@ | Set-Content (Join-Path $seedRoot 'schema.json') -Encoding utf8
@'
{
  "layers": {
    "platform-connectivity": {
      "variablesFile": "terraform/live/platform-connectivity/variables.tf",
      "variables": {
        "azfw_tier": "connectivity.firewall.tier"
      }
    }
  }
}
'@ | Set-Content (Join-Path $seedRoot 'variable-map.json') -Encoding utf8
@'
variable "azfw_tier" {
  type    = string
  default = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.azfw_tier)
    error_message = "azfw_tier must be Standard or Premium."
  }
}
'@ | Set-Content (Join-Path $seedRoot 'templates/terraform/live/platform-connectivity/variables.tf') -Encoding utf8

$seeded = Test-LzSchemaDrift -SchemaPath (Join-Path $seedRoot 'schema.json') `
                             -MappingPath (Join-Path $seedRoot 'variable-map.json') `
                             -TemplateRoot (Join-Path $seedRoot 'templates')
$seedFindings = @($seeded.Findings | Where-Object { $_.Kind -eq 'ConstraintMismatch' })
ok 'seeded mismatch fails the check'    (-not $seeded.InSync)
ok 'mismatch finding is blocking'       ($seedFindings.Count -eq 1 -and $seedFindings[0].Severity -eq 'Block')
ok 'finding names the schema field'     ($seedFindings.Count -eq 1 -and $seedFindings[0].Detail -match [regex]::Escape("'connectivity.firewall.tier'"))
ok 'finding names the variable'         ($seedFindings.Count -eq 1 -and $seedFindings[0].Detail -match [regex]::Escape("'azfw_tier'"))
ok 'finding names the rejected value'   ($seedFindings.Count -eq 1 -and $seedFindings[0].Detail -match '\[Basic\]')

# Contract #7 is directional (wizard ⊂ schema ⊂ terraform): Terraform accepting
# MORE than the schema offers is legal widening, not drift. Pin the asymmetry
# so a future "fix" does not start flagging it.
(Get-Content (Join-Path $seedRoot 'templates/terraform/live/platform-connectivity/variables.tf') -Raw) `
    -replace '\["Standard", "Premium"\]', '["Standard", "Premium", "Basic", "ExtraTierSchemaLacks"]' |
    Set-Content (Join-Path $seedRoot 'templates/terraform/live/platform-connectivity/variables.tf') -Encoding utf8
$widened = Test-LzSchemaDrift -SchemaPath (Join-Path $seedRoot 'schema.json') `
                              -MappingPath (Join-Path $seedRoot 'variable-map.json') `
                              -TemplateRoot (Join-Path $seedRoot 'templates')
ok 'wider Terraform list is not drift'  ($widened.InSync) (($widened.Findings | Where-Object { $_.Severity -eq 'Block' } | ForEach-Object { $_.Detail }) -join ' | ')
Remove-Item $seedRoot -Recurse -Force

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

Write-Host "`n== 15c. workloads-nonprod parity control ==" -ForegroundColor Cyan
# workloads-nonprod exists ONLY in the corpus — the live dogfood is prod-only —
# so it has no live counterpart and Test-LzSchemaDrift's live-vs-corpus
# comparison can never see it. The risk is that it silently falls behind
# workloads-prod whenever prod changes. This is the corpus-internal substitute:
# assert the two sibling layers agree on everything that is not
# environment-specific.
$prodVars = Get-LzTerraformVariables -Path "$repo/factory/templates/terraform/live/workloads-prod/variables.tf"
$nonprodVars = Get-LzTerraformVariables -Path "$repo/factory/templates/terraform/live/workloads-nonprod/variables.tf"
$prodNames = @($prodVars | ForEach-Object { $_.Name })
$nonprodNames = @($nonprodVars | ForEach-Object { $_.Name })

# Layer-agnostic variables: everything except the per-environment CIDR pairs
# and each layer's own subscription id.
$sharedExpected = @(
    'connectivity_subscription_id', 'default_tags',
    'primary_region', 'primary_region_code', 'dr_region', 'dr_region_code',
    'state_container_name', 'state_resource_group_name', 'state_storage_account_name'
)
$missingFromProd = @($sharedExpected | Where-Object { $_ -notin $prodNames })
$missingFromNonprod = @($sharedExpected | Where-Object { $_ -notin $nonprodNames })
ok 'prod declares the shared set'    ($missingFromProd.Count -eq 0) ($missingFromProd -join ',')
ok 'nonprod declares the shared set' ($missingFromNonprod.Count -eq 0) ($missingFromNonprod -join ',')

# Each layer owns exactly one subscription variable, and they must differ.
ok 'prod owns workload_prod_subscription_id'       ('workload_prod_subscription_id' -in $prodNames)
ok 'nonprod owns workload_nonprod_subscription_id' ('workload_nonprod_subscription_id' -in $nonprodNames)
ok 'neither layer claims the other subscription'   (('workload_nonprod_subscription_id' -notin $prodNames) -and ('workload_prod_subscription_id' -notin $nonprodNames))

# Contract #5: spoke-network declares configuration_aliases, so every caller
# must inject a providers map carrying azurerm.hub. Contract #3: the
# remote-state read must use AAD auth.
foreach ($layer in @('workloads-prod', 'workloads-nonprod')) {
    $tmpl = Get-Content "$repo/factory/templates/terraform/live/$layer/main.tf.tmpl" -Raw
    ok "$layer injects azurerm.hub (contract 5)" ($tmpl -match 'azurerm\.hub\s*=\s*azurerm')
    ok "$layer reads state with AAD (contract 3)" ($tmpl -match 'use_azuread_auth')
    ok "$layer calls spoke-network"               ($tmpl -match 'source\s*=\s*"\.\./\.\./modules/spoke-network"')
}

Write-Host "`n== 15d. NSG flow-log mapping (decision 0009) ==" -ForegroundColor Cyan
# Three wizard keys under security.nsgFlowLogs were collected and then thrown
# away — nothing in the corpus read them. Two now feed Terraform variables.
# The third, `enabled`, deliberately does NOT: the operator resolved decision
# 0009's open question 3 as "renders false for every client". The box is
# PRE-CHECKED in the wizard, so honouring it would enable a volume-driven
# meter for every client who never touched it, and — worse — the module reads
# NetworkWatcher_<region> through the default provider, which makes the FIRST
# plan in every generated repository fail red before any VNet exists.
#
# So the interesting assertion is the negative one: the fixtures all say
# enabled=true, and the render must still emit false.
ok 'fixture pre-checks the box'    ($cfg.security.nsgFlowLogs.enabled -eq $true) $cfg.security.nsgFlowLogs.enabled

$prodTfvars = Get-Content (Join-Path $out 'terraform/live/workloads-prod/terraform.auto.tfvars') -Raw
ok 'prod gate renders false'       ($prodTfvars -match '(?m)^enable_nsg_flow_logs\s*=\s*false\s*$') 'expected literal false'
ok 'prod gate is never true'       ($prodTfvars -notmatch '(?m)^enable_nsg_flow_logs\s*=\s*true\s*$')
ok 'prod retention flows through'  ($prodTfvars -match '(?m)^flow_log_retention_days\s*=\s*90\s*$')
ok 'prod TA flows through'         ($prodTfvars -match '(?m)^enable_traffic_analytics\s*=\s*true\s*$')
# The rendered file must SAY the answer was recorded and the feature is off,
# not leave a client to infer it from a bare false.
ok 'prod tfvars explains the off'  ($prodTfvars -match 'recorded in' -and $prodTfvars -match 'rendered false')
ok 'prod tfvars names the unblock' ($prodTfvars -match 'Flip this to true in a PR')

$npTfvars = Get-Content (Join-Path $nonprodOut 'terraform/live/workloads-nonprod/terraform.auto.tfvars') -Raw
ok 'nonprod gate renders false'    ($npTfvars -match '(?m)^enable_nsg_flow_logs\s*=\s*false\s*$')
ok 'nonprod retention flows'       ($npTfvars -match '(?m)^flow_log_retention_days\s*=\s*90\s*$')
ok 'nonprod TA flows through'      ($npTfvars -match '(?m)^enable_traffic_analytics\s*=\s*true\s*$')

# Proves the two live mappings are mappings and not hard-coded defaults that
# happen to match the fixture, and re-proves the gate stays false even when the
# client explicitly unchecks the box (there is no path back to true).
$flowCfgPath = Join-Path $PSScriptRoot '.out/flowlog-config.json'
$flowCfg = Clone $cfg
$flowCfg.security.nsgFlowLogs.enabled = $false
$flowCfg.security.nsgFlowLogs.retentionDays = 30
$flowCfg.security.nsgFlowLogs.trafficAnalytics = $false
$flowCfg | ConvertTo-Json -Depth 30 | Set-Content $flowCfgPath -Encoding utf8
$flowOut = Join-Path $PSScriptRoot '.out/render-flowlog-out'
if (Test-Path $flowOut) { Remove-Item $flowOut -Recurse -Force }
Invoke-LzRender -ConfigPath $flowCfgPath -OutputDirectory $flowOut -Quiet | Out-Null
$flowTfvars = Get-Content (Join-Path $flowOut 'terraform/live/workloads-prod/terraform.auto.tfvars') -Raw
ok 'retention tracks the config'   ($flowTfvars -match '(?m)^flow_log_retention_days\s*=\s*30\s*$')
ok 'TA tracks the config'          ($flowTfvars -match '(?m)^enable_traffic_analytics\s*=\s*false\s*$')
ok 'unchecked box still renders false' ($flowTfvars -match '(?m)^enable_nsg_flow_logs\s*=\s*false\s*$')
Remove-Item $flowOut -Recurse -Force
Remove-Item $flowCfgPath -Force

# The register must declare the same story the templates tell, or the next
# reader "fixes" the divergence back into a defect.
$vmap = Get-Content "$repo/factory/renderer/variable-map.json" -Raw | ConvertFrom-Json -Depth 20
foreach ($wl in @('workloads-prod', 'workloads-nonprod')) {
    $wlVars = $vmap.layers.$wl.variables
    ok "$wl maps the gate to literal:false" ($wlVars.enable_nsg_flow_logs -eq 'literal:false') $wlVars.enable_nsg_flow_logs
    ok "$wl maps retentionDays"             ($wlVars.flow_log_retention_days -eq 'security.nsgFlowLogs.retentionDays') $wlVars.flow_log_retention_days
    ok "$wl maps trafficAnalytics"          ($wlVars.enable_traffic_analytics -eq 'security.nsgFlowLogs.trafficAnalytics') $wlVars.enable_traffic_analytics
}

# Contract #4: the workspace never flows through lz-config.json. The flow-log
# wiring takes it from the connectivity remote-state read, so this change must
# not have introduced a workspace key anywhere in the register.
$mapPathValues = @()
foreach ($lyr in $vmap.layers.PSObject.Properties) {
    foreach ($v in $lyr.Value.variables.PSObject.Properties) { $mapPathValues += $v.Value }
}
# observability.logAnalytics.retentionDays is a legitimate long-standing
# mapping and is NOT what contract #4 forbids — it sets how long the workspace
# keeps data, not which workspace exists. What is forbidden is a config key
# that identifies the workspace, which is what a workspace-id/guid variable
# would consume.
$mapVarNames = @()
foreach ($lyr in $vmap.layers.PSObject.Properties) {
    foreach ($v in $lyr.Value.variables.PSObject.Properties) {
        if ($v.Value -notlike 'literal:*' -and $v.Value -notlike 'computed.*') { $mapVarNames += $v.Name }
    }
}
$workspaceIdentityVars = @($mapVarNames | Where-Object { $_ -match 'workspace_(id|guid|resource_id|region|location)$' })
ok 'contract 4: no workspace key mapped' ($workspaceIdentityVars.Count -eq 0) ($workspaceIdentityVars -join ',')
ok 'contract 4: no workspace path used'  (@($mapPathValues | Where-Object { $_ -match 'workspaceId|workspaceGuid|workspaceResourceId' }).Count -eq 0) (($mapPathValues | Where-Object { $_ -match 'workspace' }) -join ',')

# Contract #7 bounds ordering for the one numeric key: wizard ⊂ schema ⊂
# Terraform. The wizard input and the schema are both 1–365; Terraform is
# deliberately unbounded, which is legal widening. A validation block on the
# Terraform variable narrower than 1–365 would invert the ordering.
$flowSchema = $liveSchema.properties.security.properties.nsgFlowLogs.properties.retentionDays
ok 'schema retention min is 1'     ($flowSchema.minimum -eq 1) $flowSchema.minimum
ok 'schema retention max is 365'   ($flowSchema.maximum -eq 365) $flowSchema.maximum
$siteHtml = Get-Content "$repo/site/index.html" -Raw
ok 'wizard input is within schema' ($siteHtml -match 'data-path="security\.nsgFlowLogs\.retentionDays"[^>]*min="1"[^>]*max="365"')
foreach ($wl in @('workloads-prod', 'workloads-nonprod')) {
    # Segment on the next `variable "` rather than on a closing brace: the
    # variable's own comment contains NetworkWatcher_${location}, so a
    # brace-counting match truncates in the middle of the block.
    $wlRaw = Get-Content "$repo/factory/templates/terraform/live/$wl/variables.tf" -Raw
    $retBlock = [regex]::Match($wlRaw, '(?s)variable\s+"flow_log_retention_days"\s*\{(?<b>.*?)(?=\r?\nvariable\s+"|\z)')
    ok "$wl leaves retention unbounded" ($retBlock.Success -and $retBlock.Groups['b'].Value -notmatch 'validation\s*\{') ($retBlock.Groups['b'].Value -replace '\s+', ' ')
}

Write-Host "`n== 15e. Flow-log storage names are distinct (TODO 2.9) ==" -ForegroundColor Cyan
# Contract 8a used to read "one nsg-flow-logs instance per (region,
# environment), estate-wide", because the module composed a globally-unique
# storage account name with no override. Hub fw_mgmt coverage needs a second
# instance in the same region and environment as the workload one, so the
# ceiling became "names must be distinct, and the second caller must supply
# storage_account_name".
#
# No plan can prove that here — azurerm needs credentials — so the criterion is
# proved from configuration, which is where the collision is actually decided:
# the module's fallback is unchanged, the workload callers still take it, the
# connectivity callers override it, and the four resulting names are distinct.
$flowMods = @{
    live   = "$repo/terraform/modules/nsg-flow-logs"
    corpus = "$repo/factory/templates/terraform/modules/nsg-flow-logs"
}
foreach ($tree in $flowMods.Keys | Sort-Object) {
    $mVars = Get-Content "$($flowMods[$tree])/variables.tf" -Raw
    $mMain = Get-Content "$($flowMods[$tree])/main.tf" -Raw
    $sanBlock = [regex]::Match($mVars, '(?s)variable\s+"storage_account_name"\s*\{(?<b>.*?)(?=\r?\nvariable\s+"|\z)')
    ok "$tree module declares the override"  $sanBlock.Success
    ok "$tree override defaults to null"     ($sanBlock.Groups['b'].Value -match '(?m)^\s*default\s*=\s*null\s*$')
    ok "$tree override validates Azure rule" ($sanBlock.Groups['b'].Value -match '\^\[a-z0-9\]\{3,24\}\$')
    # The fallback is the pre-override expression, byte for byte: existing
    # callers must render the name they already have or an apply replaces a
    # storage account holding flow logs.
    ok "$tree fallback is unchanged"         ($mMain -match '(?m)^\s*default_storage_account_name\s*=\s*"stflowlogs\$\{var\.region_code\}\$\{var\.environment\}"\s*$')
    ok "$tree name falls back when unset"    ($mMain -match 'name\s*=\s*coalesce\(var\.storage_account_name,\s*local\.default_storage_account_name\)')
}

# Effective names, computed the way Terraform would for the fixture's regions.
$env = 'prod'
$composed = { param($code) "stflowlogs$code$env" }
$flowNames = @{}
foreach ($pair in @(@{ layer = 'workloads-prod'; code = $cfg.azure.primaryRegionCode }, @{ layer = 'workloads-prod-dr'; code = $cfg.azure.drRegionCode })) {
    $flowNames[$pair.layer] = & $composed $pair.code
}
# The workload callers must NOT set the override, or their storage accounts
# would be renamed under an estate that already has them. Scoped to the module
# blocks: the layer's remote-state read legitimately mentions
# state_storage_account_name.
foreach ($wlFile in @('terraform/live/workloads-prod/main.tf', 'factory/templates/terraform/live/workloads-prod/main.tf.tmpl')) {
    $wlRawMain = Get-Content "$repo/$wlFile" -Raw
    $wlCalls = @([regex]::Matches($wlRawMain, '(?s)module\s+"nsg_flow_logs[^"]*"\s*\{(?<b>.*?)\r?\n\}'))
    ok "$wlFile calls the module twice"  ($wlCalls.Count -eq 2) $wlCalls.Count
    $overridden = @($wlCalls | Where-Object { $_.Groups['b'].Value -match '(?m)^\s*storage_account_name\s*=' })
    ok "$wlFile keeps the composed name" ($overridden.Count -eq 0) $overridden.Count
}

# The connectivity callers must set it, in both trees and in the render.
$connSources = @{
    live     = Get-Content "$repo/terraform/live/platform-connectivity/main.tf" -Raw
    corpus   = Get-Content "$repo/factory/templates/terraform/live/platform-connectivity/main.tf.tmpl" -Raw
    rendered = Get-Content (Join-Path $out 'terraform/live/platform-connectivity/main.tf') -Raw
}
foreach ($tree in $connSources.Keys | Sort-Object) {
    $src = $connSources[$tree]
    ok "$tree hub primary overrides the name" ($src -match 'storage_account_name\s*=\s*"stflowlogshub\$\{var\.primary_region_code\}prod"')
    ok "$tree hub DR overrides the name"      ($src -match 'storage_account_name\s*=\s*"stflowlogshub\$\{var\.dr_region_code\}prod"')
    # An NVA-less hub has no fw_mgmt NSG, so the instance must not be created
    # at all — a storage account with nothing to log still bills.
    ok "$tree gates on the NSG existing"      ($src -match 'var\.enable_nsg_flow_logs\s*&&\s*length\(module\.hub_primary\.nsg_ids\)\s*>\s*0')
}
$flowNames['connectivity-primary'] = "stflowlogshub$($cfg.azure.primaryRegionCode)prod"
$flowNames['connectivity-dr'] = "stflowlogshub$($cfg.azure.drRegionCode)prod"

# The criterion itself: two instances in ONE region at ONE environment now
# plan distinct storage accounts, and every name is a legal Azure one.
ok 'primary region: two distinct names' ($flowNames['workloads-prod'] -ne $flowNames['connectivity-primary']) "$($flowNames['workloads-prod']) vs $($flowNames['connectivity-primary'])"
ok 'DR region: two distinct names'      ($flowNames['workloads-prod-dr'] -ne $flowNames['connectivity-dr']) "$($flowNames['workloads-prod-dr']) vs $($flowNames['connectivity-dr'])"
ok 'all four names distinct'            (@($flowNames.Values | Sort-Object -Unique).Count -eq 4) ($flowNames.Values -join ',')
$illegal = @($flowNames.Values | Where-Object { $_ -cnotmatch '^[a-z0-9]{3,24}$' })
ok 'every name is a legal storage name' ($illegal.Count -eq 0) ($illegal -join ',')
# The composed fallback must itself satisfy the rule the override validates,
# or the module would reject a name it generates.
ok 'fallback satisfies the validation'  ($flowNames['workloads-prod'] -cmatch '^[a-z0-9]{3,24}$') $flowNames['workloads-prod']

# hub-network's map must be empty, not null and not an index into a
# zero-length resource, when the hub deploys no NVA.
foreach ($tree in @('terraform/modules/hub-network', 'factory/templates/terraform/modules/hub-network')) {
    $hubOut = Get-Content "$repo/$tree/outputs.tf" -Raw
    $nsgBlock = [regex]::Match($hubOut, '(?s)output\s+"nsg_ids"\s*\{(?<b>.*?)(?=\r?\noutput\s+"|\z)')
    ok "$tree exposes nsg_ids"        $nsgBlock.Success
    ok "$tree keys fw_mgmt"           ($nsgBlock.Groups['b'].Value -match 'fw_mgmt\s*=\s*azurerm_network_security_group\.fw_mgmt\[0\]\.id')
    ok "$tree empties without an NVA" ($nsgBlock.Groups['b'].Value -match 'local\.has_nva\s*\?' -and $nsgBlock.Groups['b'].Value -match ':\s*\{\}')
}

# The connectivity gate follows the workload layers: default-off variable,
# literal:false mapping, and a rendered constant false.
$connVars = @(Get-LzTerraformVariables -Path "$repo/factory/templates/terraform/live/platform-connectivity/variables.tf")
$connGate = @($connVars | Where-Object { $_.Name -eq 'enable_nsg_flow_logs' })
ok 'connectivity declares the gate'   ($connGate.Count -eq 1)
ok 'connectivity gate has a default'  ($connGate.Count -eq 1 -and $connGate[0].HasDefault)
ok 'connectivity maps literal:false'  ($vmap.layers.'platform-connectivity'.variables.enable_nsg_flow_logs -eq 'literal:false') $vmap.layers.'platform-connectivity'.variables.enable_nsg_flow_logs
$connTfvars = Get-Content (Join-Path $out 'terraform/live/platform-connectivity/terraform.auto.tfvars') -Raw
ok 'connectivity gate renders false'  ($connTfvars -match '(?m)^enable_nsg_flow_logs\s*=\s*false\s*$') 'expected literal false'
ok 'connectivity gate is never true'  ($connTfvars -notmatch '(?m)^enable_nsg_flow_logs\s*=\s*true\s*$')
ok 'connectivity names the unblock'   ($connTfvars -match 'Flip this to true in a PR')

Write-Host "`n== 15f. Blob private DNS unblocks the flow-log endpoint (TODO 2.10) ==" -ForegroundColor Cyan
# Decision 0009 constraint 4 turned enable_private_endpoint off everywhere,
# because a private endpoint without a matching private DNS zone resolves to
# nothing. Follow-up (c) creates the zone in the connectivity layer and lets
# the workload layers derive the endpoint from it.
#
# Like 15e, no plan can prove this without credentials, so it is proved from
# configuration: the module refuses a half-configured endpoint, the zone and
# its hub links are gated on one variable, that variable is exported, and each
# workload caller links its spoke and derives all three endpoint arguments from
# the exported value.

# The module must fail at PLAN, not at apply, when a caller enables the
# endpoint without a subnet or a zone — enable_private_endpoint defaults to
# true while both of those default to empty.
foreach ($tree in $flowMods.Keys | Sort-Object) {
    $mMain = Get-Content "$($flowMods[$tree])/main.tf" -Raw
    $peBlock = [regex]::Match($mMain, '(?s)resource\s+"azurerm_private_endpoint"\s+"flow_logs_blob"\s*\{(?<b>.*?)\r?\n\}')
    ok "$tree module has the endpoint"       $peBlock.Success
    ok "$tree requires a subnet at plan"     ($peBlock.Groups['b'].Value -match 'condition\s*=\s*var\.private_endpoint_subnet_id\s*!=\s*""')
    ok "$tree requires a zone at plan"       ($peBlock.Groups['b'].Value -match 'condition\s*=\s*length\(var\.private_dns_zone_ids\)\s*>\s*0')
}

# The zone and both hub links are gated on one connectivity variable, and the
# zone name is the exact one Azure resolves blob privatelink records from.
foreach ($connFile in @('terraform/live/platform-connectivity/main.tf', 'factory/templates/terraform/live/platform-connectivity/main.tf.tmpl')) {
    $connSrc = Get-Content "$repo/$connFile" -Raw
    # The zone name comes from the set now (item 2.12), so the literal lives in
    # local.blob_zone_name — which is also what the output looks up by.
    ok "$connFile creates the zone"      ($connSrc -match '(?s)resource\s+"azurerm_private_dns_zone"\s+"blob"\s*\{[^}]*name\s*=\s*each\.value')
    ok "$connFile pins the blob name"    ($connSrc -match '(?m)^\s*blob_zone_name\s*=\s*"privatelink\.blob\.core\.windows\.net"\s*$')
    ok "$connFile gates the zones"       ($connSrc -match 'var\.deploy_private_dns_zones\s*\r?\n?\s*\?\s*toset\(')
    ok "$connFile zones are for_each"    ($connSrc -match '(?s)resource\s+"azurerm_private_dns_zone"\s+"blob"\s*\{[^}]*for_each\s*=\s*local\.private_dns_zones')
    ok "$connFile blank means blob"      ($connSrc -match 'length\(var\.private_dns_zones\)\s*>\s*0\s*\?\s*var\.private_dns_zones\s*:\s*\[local\.blob_zone_name\]')
    ok "$connFile moves count to key"    ($connSrc -match '(?s)moved\s*\{\s*from\s*=\s*azurerm_private_dns_zone\.blob\[0\]')
    ok "$connFile links the primary hub" ($connSrc -match '(?s)"azurerm_private_dns_zone_virtual_network_link"\s+"blob_hub_primary"\s*\{.*?virtual_network_id\s*=\s*module\.hub_primary\.hub_vnet_id')
    ok "$connFile links the DR hub"      ($connSrc -match '(?s)"azurerm_private_dns_zone_virtual_network_link"\s+"blob_hub_dr"\s*\{.*?virtual_network_id\s*=\s*module\.hub_dr\.hub_vnet_id')
    # azurerm 5.0 rejects the resource_group_name + private_dns_zone_name pair.
    ok "$connFile uses the 5.0 link arg" ($connSrc -notmatch '(?m)^\s*private_dns_zone_name\s*=')
    # Only one link per zone may register, and none of these should.
    ok "$connFile registers no VNet"     ($connSrc -notmatch 'registration_enabled\s*=\s*true')
}

# Default-off in both trees: the zone is the switch that turns the workload
# endpoints on, so it is a PR decision rather than a default.
foreach ($connVarFile in @('terraform/live/platform-connectivity/variables.tf', 'factory/templates/terraform/live/platform-connectivity/variables.tf')) {
    $zVars = @(Get-LzTerraformVariables -Path "$repo/$connVarFile")
    $zGate = @($zVars | Where-Object { $_.Name -eq 'deploy_private_dns_zones' })
    ok "$connVarFile declares the gate"  ($zGate.Count -eq 1)
    ok "$connVarFile gate defaults off"  ($zGate.Count -eq 1 -and $zGate[0].HasDefault -and (Get-Content "$repo/$connVarFile" -Raw) -match '(?s)variable\s+"deploy_private_dns_zones"\s*\{.*?default\s*=\s*false')
    # The list variable is the loosest of the three bounds (contract #7).
    $zList = @($zVars | Where-Object { $_.Name -eq 'private_dns_zones' })
    ok "$connVarFile declares the list"  ($zList.Count -eq 1)
    ok "$connVarFile list defaults empty" ((Get-Content "$repo/$connVarFile" -Raw) -match '(?s)variable\s+"private_dns_zones"\s*\{.*?default\s*=\s*\[\]')
    ok "$connVarFile validates zone names" ((Get-Content "$repo/$connVarFile" -Raw) -match 'a-z0-9\]\(\[a-z0-9-\]\*\[a-z0-9\]\)\?')
    ok "$connVarFile rejects duplicates"  ((Get-Content "$repo/$connVarFile" -Raw) -match 'distinct\(var\.private_dns_zones\)')
}

# The zone ID is exported unconditionally — an empty string when the gate is
# off — so the workload layers' remote-state read always finds the key.
foreach ($connOutFile in @('terraform/live/platform-connectivity/outputs.tf', 'factory/templates/terraform/live/platform-connectivity/outputs.tf.tmpl')) {
    $oSrc = Get-Content "$repo/$connOutFile" -Raw
    $oBlock = [regex]::Match($oSrc, '(?s)output\s+"blob_private_dns_zone_id"\s*\{(?<b>.*?)(?=\r?\noutput\s+"|\z)')
    ok "$connOutFile exports the zone ID" $oBlock.Success
    # Looked up BY NAME: a client list that omits the blob zone must yield an
    # empty string, not an index error and not the wrong zone.
    ok "$connOutFile looks the zone up by name" ($oBlock.Groups['b'].Value -match 'try\(azurerm_private_dns_zone\.blob\[[^\]]*\]\.id,\s*""\)')
    ok "$connOutFile export is ungated"   ($oBlock.Groups['b'].Value -notmatch 'count')
}

# Each workload layer: one remote-state read, links through the HUB-scoped
# provider (the zone is not in the workload subscription), and all three
# endpoint arguments derived from that one value.
$wlEndpointFiles = @(
    'terraform/live/workloads-prod/main.tf',
    'factory/templates/terraform/live/workloads-prod/main.tf.tmpl',
    'factory/templates/terraform/live/workloads-nonprod/main.tf.tmpl'
)
foreach ($wlFile in $wlEndpointFiles) {
    $wlSrc = Get-Content "$repo/$wlFile" -Raw
    ok "$wlFile reads the zone ID"       ($wlSrc -match 'blob_private_dns_zone_id\s*=\s*try\(')
    ok "$wlFile derives the enable flag" ($wlSrc -match 'blob_private_dns_enabled\s*=\s*local\.blob_private_dns_zone_id\s*!=\s*""')
    $linkBlocks = @([regex]::Matches($wlSrc, '(?s)resource\s+"azurerm_private_dns_zone_virtual_network_link"\s+"blob_spoke[^"]*"\s*\{(?<b>.*?)\r?\n\}'))
    ok "$wlFile links its spokes"        ($linkBlocks.Count -ge 1) $linkBlocks.Count
    $viaHub = @($linkBlocks | Where-Object { $_.Groups['b'].Value -match '(?m)^\s*provider\s*=\s*azurerm\.hub\s*$' })
    ok "$wlFile links via the hub alias" ($viaHub.Count -eq $linkBlocks.Count) "$($viaHub.Count)/$($linkBlocks.Count)"
    $gated = @($linkBlocks | Where-Object { $_.Groups['b'].Value -match 'count\s*=\s*local\.blob_private_dns_enabled\s*\?\s*1\s*:\s*0' })
    ok "$wlFile gates its links"         ($gated.Count -eq $linkBlocks.Count) "$($gated.Count)/$($linkBlocks.Count)"

    # Every flow-log call must set all three endpoint arguments together, or
    # the module's preconditions reject the plan.
    $wlFlowCalls = @([regex]::Matches($wlSrc, '(?s)module\s+"nsg_flow_logs[^"]*"\s*\{(?<b>.*?)\r?\n\}'))
    ok "$wlFile calls the flow module"   ($wlFlowCalls.Count -ge 1) $wlFlowCalls.Count
    foreach ($call in $wlFlowCalls) {
        $b = $call.Groups['b'].Value
        $wired = ($b -match 'enable_private_endpoint\s*=\s*local\.blob_private_dns_enabled') -and
                 ($b -match 'private_endpoint_subnet_id\s*=\s*\S+pe_subnet') -and
                 ($b -match 'private_dns_zone_ids\s*=\s*local\.blob_private_dns_enabled\s*\?\s*\[local\.blob_private_dns_zone_id\]\s*:\s*\[\]')
        ok "$wlFile wires all three args" $wired
    }
    # No caller may leave the old hardcoded false behind.
    ok "$wlFile has no hardcoded false"  ($wlSrc -notmatch 'enable_private_endpoint\s*=\s*false')
}

# The hub instances stay endpoint-less, and for the NEW reason: hub-network
# exposes no private-endpoint subnet. If that ever changes this assertion is
# the reminder to revisit them.
foreach ($hubOutFile in @('terraform/modules/hub-network/outputs.tf', 'factory/templates/terraform/modules/hub-network/outputs.tf')) {
    ok "$hubOutFile has no PE subnet" ((Get-Content "$repo/$hubOutFile" -Raw) -notmatch 'pe_subnet_id')
}

# The renderer honours the client's Private DNS answer rather than a constant,
# and the rendered tfvars says what it does and does not turn on.
ok 'gate maps to the wizard answer'  ($vmap.layers.'platform-connectivity'.variables.deploy_private_dns_zones -eq 'connectivity.privateDns.enabled') $vmap.layers.'platform-connectivity'.variables.deploy_private_dns_zones
ok 'zone list maps to the answer'    ($vmap.layers.'platform-connectivity'.variables.private_dns_zones -eq 'connectivity.privateDns.zones') $vmap.layers.'platform-connectivity'.variables.private_dns_zones
$expectedZoneGate = if ($cfg.connectivity.privateDns.enabled) { 'true' } else { 'false' }
ok 'gate renders the answer'         ($connTfvars -match "(?m)^deploy_private_dns_zones\s*=\s*$expectedZoneGate\s*$") $expectedZoneGate
ok 'zone list renders'               ($connTfvars -match '(?m)^private_dns_zones\s*=\s*\[')
ok 'tfvars says endpoints stay off'  ($connTfvars -match 'gated there on')

# The endpoint path must remain inert in a rendered repository: the zone may be
# on, but the flow-log gate that creates the endpoints is still a constant
# false, so nothing per-gigabyte appears from a first apply.
$renderedProd = Get-Content (Join-Path $out 'terraform/live/workloads-prod/terraform.auto.tfvars') -Raw
ok 'rendered prod flow gate is off'  ($renderedProd -match '(?m)^enable_nsg_flow_logs\s*=\s*false\s*$')

Write-Host "`n== 15g. The client's private DNS zone list is what gets created (TODO 2.12) ==" -ForegroundColor Cyan
# The wizard has always collected a LIST of zones and a centralizedInHub flag.
# Item 2.10 consumed neither: it created one hardcoded blob zone. Both halves
# of that gap are closed here — the list is rendered, and the flag that has no
# implementation is refused rather than silently ignored.

# Contract #7 ordering, checked as an ordering rather than three separate
# regexes: every zone the WIZARD would accept must be accepted by the SCHEMA,
# and every zone the schema accepts must be accepted by TERRAFORM.
$zoneSchema = Get-Content "$repo/factory/schema/lz-config.schema.json" -Raw | ConvertFrom-Json -Depth 30
$schemaZones = $zoneSchema.properties.connectivity.properties.privateDns.properties.zones
ok 'schema constrains zone items'   ($null -ne $schemaZones.items.pattern) $schemaZones.items.pattern
ok 'schema caps zone length'        ($schemaZones.items.maxLength -eq 253) $schemaZones.items.maxLength
ok 'schema rejects duplicates'      ($schemaZones.uniqueItems -eq $true)
$appJs = Get-Content "$repo/site/app.js" -Raw
ok 'wizard carries a zone regex'    ($appJs -match 'dnsZone:\s*/')
ok 'wizard validates the list'      ($appJs -match 'RE\.dnsZone\.test\(z\)')
# The three patterns must be the same expression, which is the only way to be
# sure none of the three is looser than the one to its right.
$tfPattern = ([regex]::Match((Get-Content "$repo/terraform/live/platform-connectivity/variables.tf" -Raw), 'regex\("(?<p>\^\[a-z0-9\][^"]*)"')).Groups['p'].Value
$jsPattern = ([regex]::Match($appJs, 'dnsZone:\s*/(?<p>\^\[a-z0-9\][^/]*)/')).Groups['p'].Value
$normalize = { param($x) $x -replace '\\\\', '\' }
ok 'terraform pattern found'        ($tfPattern -ne '') $tfPattern
ok 'wizard pattern matches schema'  ($jsPattern -eq (& $normalize $schemaZones.items.pattern)) "$jsPattern vs $($schemaZones.items.pattern)"
ok 'schema pattern matches tf'      ((& $normalize $schemaZones.items.pattern) -eq (& $normalize $tfPattern)) "$($schemaZones.items.pattern) vs $tfPattern"

# centralizedInHub = false has no implementation (contract 9), so it must be
# refused at BOTH ends rather than collected and dropped.
ok 'wizard refuses decentralized'   ($appJs -match 'centralizedInHub === false')
$guardSrc = Get-Content "$repo/factory/renderer/public/Test-LzRenderGuards.ps1" -Raw
ok 'a guard refuses decentralized'  ($guardSrc -match "Id 'G23'")
ok 'the guard blocks, not warns'    ($guardSrc -notmatch "(?s)Id 'G23'.*?-Severity\s+'Warn'")
# Guard IDs are handed out by hand and are NOT in file order — G21 was already
# taken, several screens above G20, when G23 was written, and the duplicate
# shipped. These two assertions are what would have caught it, and what caught
# the older drift TODO item 2.13 fixed.
#
# An ID may appear at more than one call site ONLY when it is one condition
# with several variants: G22 raises separately for a missing primary and a
# missing DR spoke CIDR, which is one failure a client fixes in one place. It
# used to cover a missing SUBSCRIPTION as well — a different failure with a
# different remediation, which is why the README's single G22 row described
# only half of it. That case is now G24.
$multiUseGuardIds = @('G22')
$guardIds = @([regex]::Matches($guardSrc, "Id '(?<id>G\d+)'") | ForEach-Object { $_.Groups['id'].Value })
$dupeGuardIds = @($guardIds | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name } | Sort-Object)
$unexpectedDupes = @($dupeGuardIds | Where-Object { $_ -notin $multiUseGuardIds })
ok 'no undeclared repeated IDs'     ($unexpectedDupes.Count -eq 0) ($unexpectedDupes -join ',')
ok 'declared repeats still repeat'  ((($dupeGuardIds -join ',')) -eq ($multiUseGuardIds -join ',')) ($dupeGuardIds -join ',')

# Every ID the chain can raise must be documented. G15 sat undocumented for its
# whole life because nothing checked; a guard a client hits and cannot look up
# is a worse failure than the one it reports.
# Scoped to TABLE ROWS and the advisory sentence — deliberately NOT the whole
# file. Scanning the whole README made this check vacuous: the paragraph
# explaining the G15 gap mentions G15, so deleting its row still "documented"
# it. A guard is documented when it has a row, not when prose names it.
$guardReadmeLines = @(Get-Content "$repo/factory/renderer/README.md")
$guardDocLines = @($guardReadmeLines | Where-Object { $_ -match '^\|\s*G\d' -or $_ -match 'are advisory warnings' })
$documentedIds = @([regex]::Matches(($guardDocLines -join "`n"), '\bG(?<n>\d{2})\b') | ForEach-Object { "G$($_.Groups['n'].Value)" } | Sort-Object -Unique)
$undocumentedIds = @(@($guardIds | Sort-Object -Unique) | Where-Object { $_ -notin $documentedIds })
ok 'every guard ID is documented'   ($undocumentedIds.Count -eq 0) ($undocumentedIds -join ',')
# And nothing documented has been deleted from the chain without the row going.
$phantomIds = @($documentedIds | Where-Object { $_ -notin $guardIds -and $_ -ne 'G00' })
ok 'no phantom guard rows'          ($phantomIds.Count -eq 0) ($phantomIds -join ',')
ok 'G23 is documented'              ((Get-Content "$repo/factory/renderer/README.md" -Raw) -match '\|\s*G23\s*\|')
# An absent key must read as the centralized answer, or every config written
# before this field existed would suddenly fail to render.
ok 'G23 defaults to centralized'    ($guardSrc -match "centralizedInHub' -Default \`$true")

# A config that unticks it renders nothing at all.
$dnsCfgPath = Join-Path $PSScriptRoot '.out/decentralized-dns-config.json'
$dnsBad = Clone $cfg
$dnsBad.connectivity.privateDns.enabled = $true
$dnsBad.connectivity.privateDns.centralizedInHub = $false
$dnsBad | ConvertTo-Json -Depth 30 | Set-Content $dnsCfgPath -Encoding utf8
$dnsOut = Join-Path $PSScriptRoot '.out/render-dns-out'
if (Test-Path $dnsOut) { Remove-Item $dnsOut -Recurse -Force }
ok 'decentralized config throws'    (throws { Invoke-LzRender -ConfigPath $dnsCfgPath -OutputDirectory $dnsOut -Quiet })
ok 'nothing written when blocked'   (-not (Test-Path (Join-Path $dnsOut 'README.md')))

# The promise that had nothing behind it must be gone from both places that
# made it — an empty list means the blob zone, not a derived CAF set.
ok 'schema drops the CAF promise'   ($schemaZones.description -notmatch 'use the CAF default set') $schemaZones.description
ok 'schema states what blank does'  ($schemaZones.description -match 'privatelink\.blob\.core\.windows\.net alone')
ok 'wizard drops the CAF promise'   ((Get-Content "$repo/site/index.html" -Raw) -notmatch 'CAF default zone set')

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
    (Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw) -match 'LZ_IMPORT_ALLOW_STALE'
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
