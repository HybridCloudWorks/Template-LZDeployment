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
$globalTfvars = Get-Content (Join-Path $out 'terraform/live/global/terraform.auto.tfvars') -Raw
ok 'global references avm-ptn-alz by registry pin' ($globalMain -match 'source\s+=\s+"Azure/avm-ptn-alz/azurerm"' -and $globalMain -match 'version\s+=\s+"0\.21\.0"')
ok 'alz provider pins the library'   ($globalMain -match 'library_references' -and $globalMain -match '2026\.04\.2')
$mgmtMain = Get-Content (Join-Path $out 'terraform/live/platform-management/main.tf') -Raw
ok 'management references avm-ptn-alz-management' ($mgmtMain -match 'source\s+=\s+"Azure/avm-ptn-alz-management/azurerm"')
ok 'management wires the daily ingestion cap' ($mgmtMain -match 'log_analytics_workspace_daily_quota_gb\s+=\s+var\.log_daily_quota_gb')

# The ALZ policy default values. Unsupplied, an assignment is created from the
# placeholder in the library's own assignment file, and nothing here would ever
# notice: init and validate never reach the provider's default resolution, and
# no gate in this factory runs a plan.
$mgmtOutputs = Get-Content (Join-Path $out 'terraform/live/platform-management/outputs.tf') -Raw
foreach ($export in @(
        'ama_user_assigned_identity_id', 'ama_user_assigned_identity_name',
        'dcr_vm_insights_id', 'dcr_defender_sql_id', 'dcr_change_tracking_id')) {
    ok "management exports $export" ($mgmtOutputs -match ('output "' + $export + '"'))
}
# The map keys are the module's, fixed by its variable *type* at the pinned
# version rather than by a default, so a typo here is a plan-time failure.
ok 'AMA identity read by the module key' ($mgmtOutputs -match 'user_assigned_identity_ids\["ama"\]')
ok 'DCR keys match the module contract' (
    $mgmtOutputs -match 'data_collection_rule_ids\["vm_insights"\]' -and
    $mgmtOutputs -match 'data_collection_rule_ids\["defender_sql"\]' -and
    $mgmtOutputs -match 'data_collection_rule_ids\["change_tracking"\]')
ok 'identity name is derived from its ID, not restated' ($mgmtOutputs -match 'reverse\(split\("/"')

$pdvBlock = if ($globalMain -match '(?s)policy_default_values\s*=\s*\{(.*?)\n  \}') { $Matches[1] } else { '' }
$pdvKeys = @([regex]::Matches($pdvBlock, '(?m)^\s{4}([a-z0-9_]+)\s*=\s*jsonencode') | ForEach-Object { $_.Groups[1].Value })
# All fourteen the pinned library declares. The count is asserted rather than
# the names, because the names are already checked one by one below and a
# library bump that adds a value must fail here rather than pass quietly.
ok 'global supplies every policy default value' ($pdvKeys.Count -eq 14) ($pdvKeys -join ',')
ok 'AMA defaults come from management remote state' (
    $pdvBlock -match 'ama_user_assigned_managed_identity_id[\s\S]*?terraform_remote_state\.management')
# Composed from config on purpose: platform-connectivity applies AFTER this
# layer, so reading these back would invert the deploy order.
ok 'private DNS RG name matches the connectivity layer naming' (
    $pdvBlock -match 'rg-\$\{var\.org_prefix\}-connectivity-\$\{var\.primary_region_code\}')


ok 'global tfvars carries the naming inputs' (
    $globalTfvars -match 'org_prefix\s+=' -and $globalTfvars -match 'primary_region_code\s+=')

# The management-group IDs are defined by the pinned ALZ library architecture,
# not by us. A default that names a group the library does not define places
# subscriptions into a management group that will never exist. Verified against
# platform/alz@2026.04.2: the sandbox group is `sandbox`, singular.
$globalVars = Get-Content (Join-Path $out 'terraform/live/global/variables.tf') -Raw
ok 'sandbox MG default matches the library' ($globalVars -match '(?s)variable "sandbox_management_group_id".*?default\s+=\s+"sandbox"')
ok 'sandbox MG default is not the plural typo' ($globalVars -notmatch 'default\s+=\s+"sandboxes"')

# The emitted apply workflow is workflow_dispatch-only. A README promising that
# a merge deploys ships a false statement to every generated repository.
$genReadme = Get-Content (Join-Path $out 'README.md') -Raw
ok 'README does not claim merging applies' ($genReadme -notmatch 'Merging to\s+`?\w*`?\s*\r?\n?runs `terraform apply`')
ok 'README names the dispatch-gated apply' ($genReadme -match 'merging does not deploy' -and $genReadme -match 'workflow_dispatch')
$connMain = Get-Content (Join-Path $out 'terraform/live/platform-connectivity/main.tf') -Raw
ok 'hub-spoke fixture emits hub-and-spoke module' ($connMain -match 'avm-ptn-alz-connectivity-hub-and-spoke-vnet')

# The firewall answer has to reach tfvars. It is the layer's largest recurring
# cost, the module takes it as a plain boolean, and the variable now carries no
# default — so an unemitted line is a hard render failure, not a silent "true".
$connTfvars = Get-Content (Join-Path $out 'terraform/live/platform-connectivity/terraform.auto.tfvars') -Raw
ok 'connectivity tfvars carries the firewall answer' ($connTfvars -match 'firewall_enabled\s+=\s+true')
ok 'connectivity tfvars carries the bastion answer'  ($connTfvars -match 'deploy_bastion\s+=\s+(true|false)')

# The two layers agree on a resource-group name by convention, not by reference:
# global composes the name it hands Deploy-Private-DNS-Zones, and connectivity is
# what actually creates the group. Nothing links them, and they apply in that
# order, so a rename on either side would send the DINE policy's records to a
# resource group that does not exist — with no gate noticing, because both files
# stay valid HCL. Compare the literal skeletons with the interpolations masked:
# the region interpolation differs by design (global uses the primary region,
# connectivity iterates hubs), so only the fixed segments can be compared.
$connRgName = if ($connMain -match '(?s)resource "azurerm_resource_group" "connectivity"\s*\{.*?\n\s*name\s*=\s*"([^"]+)"') { $Matches[1] } else { '' }
$globalDnsRg = if ($pdvBlock -match '(?s)private_dns_zone_resource_group_name\s*=\s*jsonencode\(\{\s*\n\s*value\s*=\s*"([^"]+)"') { $Matches[1] } else { '' }
$maskInterp = { param($t) ($t -replace '\$\{[^}]+\}', '<>') }
ok 'both layers name the connectivity resource group' ($connRgName -and $globalDnsRg) "conn='$connRgName' global='$globalDnsRg'"
ok 'the private-DNS resource group contract holds across layers' (
    (& $maskInterp $connRgName) -eq (& $maskInterp $globalDnsRg)) `
    "connectivity creates '$connRgName' but global tells the policy '$globalDnsRg'"

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
$schemaVersion = (Get-Content "$repo/factory/schema/lz-config.schema.json" -Raw | ConvertFrom-Json -Depth 40).properties.schemaVersion.const
ok 'answer record round-trips'      ("$($answerRecord.schemaVersion)" -eq $schemaVersion) "record: $($answerRecord.schemaVersion); schema: $schemaVersion"
$renovate = Get-Content (Join-Path $out 'renovate.json') -Raw | ConvertFrom-Json -Depth 10
ok 'renovate targets terraform manager' (@($renovate.packageRules[0].matchManagers) -contains 'terraform')

$residual = Select-String -Path (Get-ChildItem $out -Recurse -File).FullName -Pattern '(?<!\$)\{\{[^}]*\}\}' -AllMatches -ErrorAction SilentlyContinue |
    Where-Object { $_.Line -notmatch '\$\{\{' }
ok 'zero residual factory tokens'   (@($residual).Count -eq 0) (@($residual | Select-Object -First 3 | ForEach-Object { $_.Path + ':' + $_.LineNumber }) -join '; ')

Write-Host "`n== 11b. Log Analytics daily ingestion cap ==" -ForegroundColor Cyan
# -1 is the wizard's spelling of "uncapped". It must never reach tfvars: the
# module's uncapped value is null, and -1 would fail the variable validation.
$mgmtTfvars = Get-Content (Join-Path $out 'terraform/live/platform-management/terraform.auto.tfvars') -Raw
ok 'uncapped config emits no quota line' ($mgmtTfvars -notmatch 'log_daily_quota_gb')

$cfgQuota = Get-Content "$PSScriptRoot/fixtures/azurerm-config.json" -Raw | ConvertFrom-Json -Depth 30
$cfgQuota.observability.logAnalytics.dailyQuotaGb = 25
$quotaConfigPath = Join-Path ([IO.Path]::GetTempPath()) "lz-quota-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
$cfgQuota | ConvertTo-Json -Depth 30 | Set-Content $quotaConfigPath -Encoding utf8
$outQuota = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
try {
    $null = Invoke-LzRender -ConfigPath $quotaConfigPath -OutputDirectory $outQuota -Force -Quiet
    $quotaTfvars = Get-Content (Join-Path $outQuota 'terraform/live/platform-management/terraform.auto.tfvars') -Raw
    ok 'a real cap reaches tfvars' ($quotaTfvars -match 'log_daily_quota_gb\s+=\s+25')
}
finally {
    Remove-Item -Recurse -Force $outQuota -ErrorAction SilentlyContinue
    Remove-Item -Force $quotaConfigPath -ErrorAction SilentlyContinue
}

Write-Host "`n== 11c. Declining the firewall ==" -ForegroundColor Cyan
# ADR 0017 amended: the AVM connectivity patterns accept firewall_enabled=false.
# Before this, the wizard asked which tier and never whether, and the answer
# could not be expressed at all.
$cfgNoFw = Get-Content "$PSScriptRoot/fixtures/azurerm-config.json" -Raw | ConvertFrom-Json -Depth 30
$cfgNoFw.connectivity.firewall.enabled = $false
$cfgNoFw.connectivity.bastion.enabled = $false
$noFwPath = Join-Path ([IO.Path]::GetTempPath()) "lz-nofw-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
$cfgNoFw | ConvertTo-Json -Depth 30 | Set-Content $noFwPath -Encoding utf8
$outNoFw = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
try {
    $null = Invoke-LzRender -ConfigPath $noFwPath -OutputDirectory $outNoFw -Force -Quiet
    $noFwTfvars = Get-Content (Join-Path $outNoFw 'terraform/live/platform-connectivity/terraform.auto.tfvars') -Raw
    ok 'declined firewall renders as false' ($noFwTfvars -match 'firewall_enabled\s+=\s+false')
    ok 'declined bastion renders as false'  ($noFwTfvars -match 'deploy_bastion\s+=\s+false')
    $noFwMain = Get-Content (Join-Path $outNoFw 'terraform/live/platform-connectivity/main.tf') -Raw
    ok 'module still gates on the variable' ($noFwMain -match 'firewall\s+=\s+var\.firewall_enabled')
}
finally {
    Remove-Item -Recurse -Force $outNoFw -ErrorAction SilentlyContinue
    Remove-Item -Force $noFwPath -ErrorAction SilentlyContinue
}

Write-Host "`n== 12. Full render — Virtual WAN fixture ==" -ForegroundColor Cyan
$outVwan = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
$null = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/vwan-config.json" -OutputDirectory $outVwan -Quiet
$connVwan = Get-Content (Join-Path $outVwan 'terraform/live/platform-connectivity/main.tf') -Raw
ok 'vwan fixture emits virtual-wan module' ($connVwan -match 'avm-ptn-alz-connectivity-virtual-wan' -and $connVwan -match '0\.17\.1')
ok 'vwan fixture omits hub-and-spoke'      ($connVwan -notmatch 'hub-and-spoke-vnet')

Write-Host "`n== 12b. Policy selection reaches the layer ==" -ForegroundColor Cyan
# policy_assignments_to_modify is keyed by MANAGEMENT GROUP while the client
# answers per assignment, and most of the library's assignments are carried by
# more than one group. Getting that fan-out wrong is the failure this section
# exists to catch: a change that reaches one group and not the others leaves the
# same policy enforced in half the estate.
$catalog = Get-Content "$repo/site/alz-policy-catalog.json" -Raw | ConvertFrom-Json -Depth 30
$selPath = Join-Path ([IO.Path]::GetTempPath()) "lz-policy-sel-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
$outSel = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
try {
    $selConfig = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
    $selConfig.governance | Add-Member -NotePropertyName policySelection -NotePropertyValue ([pscustomobject]@{
            groups      = [pscustomobject]@{ ddos = $false; 'aks-hardening' = $false }
            assignments = [pscustomobject]@{
                # Both halves set, but Default is what the library already says:
                # only the real delta may travel.
                'Deny-Public-IP' = [pscustomobject]@{ creationEnabled = $false; enforcementMode = 'Default' }
            }
            values      = [pscustomobject]@{ email_security_contact = 'secops@example.test' }
        }) -Force
    $selConfig.governance.policyBaseline.enforcementMode = 'deny'
    $selConfig | ConvertTo-Json -Depth 40 | Set-Content $selPath -Encoding utf8

    $null = Invoke-LzRender -ConfigPath $selPath -OutputDirectory $outSel -Quiet
    $selTfvars = Get-Content (Join-Path $outSel 'terraform/live/global/terraform.auto.tfvars') -Raw

    $aks = @($catalog.groups | Where-Object { $_.id -eq 'aks-hardening' }).assignments
    ok 'a disabled group turns off every assignment it carries' `
    (@($aks | Where-Object { $selTfvars -match "(?s)`"$([regex]::Escape($_))`"\s*=\s*\{[^}]*creation_enabled\s*=\s*false" }).Count -eq @($aks).Count) `
    ($aks -join ', ')
    ok 'a disabled group turns off nothing else' ($selTfvars -notmatch '"Deny-Storage-http"')
    ok 'the DDoS assignment follows its group' ($selTfvars -match '"Enable-DDoS-VNET"\s*=')
    ok 'a per-assignment override reaches the layer' `
    ($selTfvars -match '(?s)"Deny-Public-IP"\s*=\s*\{[^}]*creation_enabled\s*=\s*false')
    # Only deltas: an enforcement mode the library already has is not a change.
    ok 'an enforcement mode equal to the library is not emitted' `
    ($selTfvars -notmatch '(?s)"Deny-Public-IP"\s*=\s*\{[^}]*enforcement_mode')
    ok 'deny leaves the library enforcement alone' ($selTfvars -notmatch 'DoNotEnforce')

    # Every changed assignment must carry its management groups, or the layer's
    # inversion silently drops the change.
    $changed = [regex]::Match($selTfvars, '(?s)policy_assignment_changes\s*=\s*\{(?<body>.*?)\n\}').Groups['body'].Value
    $names = @([regex]::Matches($changed, '(?m)^\s{2}"(?<n>[^"]+)"\s*=') | ForEach-Object { $_.Groups['n'].Value })
    $scopeBody = [regex]::Match($selTfvars, '(?s)policy_assignment_management_groups\s*=\s*\{(?<body>.*?)\n\}').Groups['body'].Value
    $scoped = @([regex]::Matches($scopeBody, '(?m)^\s{2}"(?<n>[^"]+)"\s*=') | ForEach-Object { $_.Groups['n'].Value })
    ok 'every changed assignment carries its management groups' `
    (@($names | Where-Object { $_ -notin $scoped }).Count -eq 0) `
    (($names | Where-Object { $_ -notin $scoped }) -join ', ')
    ok 'and nothing is scoped that was not changed' `
    (@($scoped | Where-Object { $_ -notin $names }).Count -eq 0)
    # The multi-group case is the one worth naming explicitly.
    $multi = @($names | Where-Object { @($catalog.assignments.$_.managementGroups).Count -gt 1 })
    foreach ($name in $multi) {
        $expected = @($catalog.assignments.$name.managementGroups)
        $line = [regex]::Match($scopeBody, "(?m)^\s{2}`"$([regex]::Escape($name))`"\s*=\s*(?<v>\[.*\])$").Groups['v'].Value
        ok "$name names all $($expected.Count) of its management groups" `
        (@($expected | Where-Object { $line -notmatch [regex]::Escape("`"$_`"") }).Count -eq 0) $line
    }

    # The audit baseline is the wizard default, and it must reach exactly the
    # deny-class assignments — never a DeployIfNotExists one, whose remediation
    # DoNotEnforce would silently stop.
    $selConfig.governance.policyBaseline.enforcementMode = 'audit'
    $selConfig | ConvertTo-Json -Depth 40 | Set-Content $selPath -Encoding utf8
    Remove-Item -Recurse -Force $outSel -ErrorAction SilentlyContinue
    $null = Invoke-LzRender -ConfigPath $selPath -OutputDirectory $outSel -Quiet
    $auditTfvars = Get-Content (Join-Path $outSel 'terraform/live/global/terraform.auto.tfvars') -Raw
    $downgraded = @([regex]::Matches($auditTfvars, '(?m)^\s{2}"(?<n>[^"]+)"\s*=\s*\{\r?\n\s+enforcement_mode\s*=\s*"DoNotEnforce"') |
        ForEach-Object { $_.Groups['n'].Value })
    # An assignment the client turned off is not downgraded — it is not created
    # at all, so it has no enforcement mode to state.
    $turnedOff = @($aks) + @('Enable-DDoS-VNET', 'Deny-Public-IP')
    $expectedDeny = @($catalog.assignments.PSObject.Properties |
        Where-Object { $_.Value.denyClass -and $_.Value.libraryEnforcementMode -eq 'Default' -and $_.Name -notin $turnedOff } |
        ForEach-Object { $_.Name })
    ok 'an assignment that is never created carries no enforcement mode' `
    ($auditTfvars -notmatch '(?s)"Deny-Priv-Esc-AKS"\s*=\s*\{[^}]*enforcement_mode')
    ok 'audit downgrades every deny-class assignment' `
    (@($expectedDeny | Where-Object { $_ -notin $downgraded }).Count -eq 0) `
    (($expectedDeny | Where-Object { $_ -notin $downgraded }) -join ', ')
    ok 'audit downgrades nothing else' `
    (@($downgraded | Where-Object { $_ -notin $expectedDeny }).Count -eq 0) `
    (($downgraded | Where-Object { $_ -notin $expectedDeny }) -join ', ')
    ok 'no remediation policy is downgraded' `
    (@($downgraded | Where-Object { $_ -like 'Deploy-*' -or $_ -like 'Enable-*' }).Count -eq 0)
}
finally {
    Remove-Item -Recurse -Force $outSel -ErrorAction SilentlyContinue
    Remove-Item -Force $selPath -ErrorAction SilentlyContinue
}

Write-Host "`n== 12c. The policy guardrail speaks the AVM idiom ==" -ForegroundColor Cyan
# The generated repository's required `policy` status check rejected added
# lines matching the bespoke corpus's `effect = "Audit"`. The AVM ALZ pattern
# says enforcement_mode and creation_enabled instead, so against the corpus
# this repository actually emits, the check read as a control and enforced
# nothing.
$guard = Get-Content (Join-Path $out '.github/workflows/policy-diff-guardrails.yml') -Raw
ok 'still rejects the bespoke spelling' ($guard -match 'effect\[\[:space:\]\]\*=\[\[:space:\]\]\*"\(Disabled\|Audit\)"')
ok 'rejects an AVM enforcement downgrade' ($guard -match 'enforcement_mode\[\[:space:\]\]\*=\[\[:space:\]\]\*"DoNotEnforce"')
ok 'rejects an AVM creation downgrade'    ($guard -match 'creation_enabled\[\[:space:\]\]\*=\[\[:space:\]\]\*false')
# The exemption has to be narrow, or the check is decorative in the other
# direction: every generated .tf would carry a blanket pass.
ok 'exempts a regeneration, not a header' ($guard -match 'record_changed' -and $guard -match 'lz-config\.json')
ok 'the exemption needs the stamp to move' ($guard -match [regex]::Escape('[0-9]+\.[0-9]+\.[0-9]+ on '))
ok 'the job id stays the required check'  ($guard -match '(?m)^  policy:$')

Write-Host "`n== 12d. Client-named management groups ==" -ForegroundColor Cyan
# The custom strategy renames the pinned library's groups; it does not re-shape
# them. Moving a group under a different parent would change which archetype —
# and so which policy set — governs everything beneath it, and management-group
# IDs are immutable in Azure, so that is a one-way mistake per client.
$mgPath = Join-Path ([IO.Path]::GetTempPath()) "lz-mg-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
$outMg = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
try {
    $mgConfig = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
    $mgConfig.azure.managementGroups.strategy = 'custom'
    $mgConfig.azure.managementGroups.workloadPlacement = 'online'
    $mgConfig.azure.managementGroups | Add-Member -NotePropertyName customHierarchy -NotePropertyValue ([pscustomobject]@{
            alz          = [pscustomobject]@{ id = 'contoso-alz'; displayName = 'Contoso Landing Zones' }
            platform     = [pscustomobject]@{ id = 'contoso-platform' }
            landingzones = [pscustomobject]@{ id = 'contoso-lz' }
            online       = [pscustomobject]@{ id = 'contoso-online' }
            management   = [pscustomobject]@{ id = 'contoso-mgmt' }
        }) -Force
    $mgConfig | ConvertTo-Json -Depth 40 | Set-Content $mgPath -Encoding utf8

    $null = Invoke-LzRender -ConfigPath $mgPath -OutputDirectory $outMg -Quiet
    $archPath = Join-Path $outMg "terraform/live/global/lib/architecture_definitions/$($mgConfig.organization.companyShortName.ToLowerInvariant()).alz_architecture_definition.json"
    ok 'a custom strategy emits a local architecture definition' (Test-Path $archPath) $archPath
    $arch = Get-Content $archPath -Raw | ConvertFrom-Json -Depth 20
    $archById = @{}
    foreach ($g in $arch.management_groups) { $archById[$g.id] = $g }

    $catalog = Get-Content "$repo/site/alz-policy-catalog.json" -Raw | ConvertFrom-Json -Depth 30
    ok 'every library group is carried over' ($arch.management_groups.Count -eq @($catalog.managementGroups).Count) `
        "emitted $($arch.management_groups.Count), library $(@($catalog.managementGroups).Count)"
    ok 'renamed groups take the client id' ($archById.ContainsKey('contoso-alz') -and $archById.ContainsKey('contoso-mgmt'))
    ok 'unrenamed groups keep the library id' ($archById.ContainsKey('corp') -and $archById.ContainsKey('sandbox'))
    # The edge is the part that breaks silently: a renamed parent whose children
    # still point at the library name creates orphans no archetype governs.
    ok 'parent edges follow the rename' ($archById['contoso-platform'].parent_id -eq 'contoso-alz')
    ok 'an unrenamed child follows a renamed parent' ($archById['corp'].parent_id -eq 'contoso-lz')
    ok 'the root has no parent' ($null -eq $archById['contoso-alz'].parent_id)
    ok 'archetypes are never rewritten' ((@($archById['contoso-alz'].archetypes) -join ',') -eq 'root')
    ok 'nothing is marked pre-existing' (@($arch.management_groups | Where-Object { $_.exists }).Count -eq 0)
    # Every parent must resolve to a group in the same file, or the apply
    # creates a hierarchy with a dangling edge.
    $dangling = @($arch.management_groups | Where-Object { $_.parent_id -and -not $archById.ContainsKey($_.parent_id) })
    ok 'no parent edge dangles' ($dangling.Count -eq 0) (($dangling | ForEach-Object { "$($_.id) -> $($_.parent_id)" }) -join ', ')

    $mgMain = Get-Content (Join-Path $outMg 'terraform/live/global/main.tf') -Raw
    ok 'the local library composes with the pinned one' `
    ($mgMain -match '(?s)library_references\s*=\s*\[.*?path\s*=\s*"platform/alz".*?custom_url\s*=\s*"\$\{path\.root\}/lib"')
    $mgTfvars = Get-Content (Join-Path $outMg 'terraform/live/global/terraform.auto.tfvars') -Raw
    ok 'architecture_name selects the client architecture' ($mgTfvars -match "architecture_name\s+=\s+`"$($mgConfig.organization.companyShortName.ToLowerInvariant())`"")
    # Placement targets must follow the renames or every subscription is placed
    # into a management group that was never created.
    ok 'placement follows the rename' ($mgTfvars -match 'management_management_group_id\s+=\s+"contoso-mgmt"')
    ok 'an unrenamed placement target stays the library id' ($mgTfvars -match 'identity_management_group_id\s+=\s+"identity"')
    ok 'workloadPlacement chooses the group' ($mgTfvars -match 'workload_management_group_id\s+=\s+"contoso-online"')
}
finally {
    Remove-Item -Recurse -Force $outMg -ErrorAction SilentlyContinue
    Remove-Item -Force $mgPath -ErrorAction SilentlyContinue
}

# G29's "renames nothing" must mean the effective names are the library's, not
# that the map is empty: a non-empty map that changes nothing still emits a
# local architecture definition, pinning the estate to a copy of the library
# that a bump can no longer update.
$g29Catalog = Get-Content "$repo/site/alz-policy-catalog.json" -Raw | ConvertFrom-Json -Depth 30
$g29Root = $g29Catalog.managementGroups[0]
foreach ($shape in @(
        @{ label = 'an empty rename map'; value = [pscustomobject]@{} },
        @{ label = 'an empty rename entry'; value = [pscustomobject]@{ "$($g29Root.id)" = [pscustomobject]@{} } },
        @{ label = 'a rename restating the library name'; value = [pscustomobject]@{ "$($g29Root.id)" = [pscustomobject]@{ id = $g29Root.id; displayName = $g29Root.displayName } } }
    )) {
    $g29Config = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
    $g29Config.azure.managementGroups.strategy = 'custom'
    $g29Config.azure.managementGroups | Add-Member -NotePropertyName customHierarchy -NotePropertyValue $shape.value -Force
    $hits = @((Test-LzRenderGuards -Config $g29Config).Violations |
        Where-Object { $_.Id -eq 'G29' -and $_.Message -match 'resolves to its library name' })
    ok "G29 refuses $($shape.label)" ($hits.Count -eq 1)
}

# The standard strategy must stay exactly as it was: the pinned library's own
# architecture, no local library, no emitted file.
$stdMain = Get-Content (Join-Path $out 'terraform/live/global/main.tf') -Raw
ok 'a standard strategy emits no local library' ($stdMain -notmatch 'custom_url')
ok 'and selects the library architecture' ((Get-Content (Join-Path $out 'terraform/live/global/terraform.auto.tfvars') -Raw) -match 'architecture_name\s+=\s+"alz"')
ok 'and no architecture definition is written' (-not (Test-Path (Join-Path $out 'terraform/live/global/lib')))

Write-Host "`n== 12e. HCP Terraform: state only ==" -ForegroundColor Cyan
# Decision 0023 partially reverses 0015. The whole point of "state only" is the
# destroy gate: both emitted workflows refuse a destroy by reading a SAVED PLAN
# FILE, and TFC remote runs cannot produce one. If remote execution ever became
# reachable, that gate would disappear from both workflows with no error.
$hcpPath = Join-Path ([IO.Path]::GetTempPath()) "lz-hcp-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
$outHcp = Join-Path ([IO.Path]::GetTempPath()) "lz-render-test-$([guid]::NewGuid().ToString('n').Substring(0,8))"
try {
    $hcpConfig = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
    $hcpConfig.backend.type = 'hcp-terraform'
    $hcpConfig.backend | Add-Member -NotePropertyName hcpTerraform -NotePropertyValue ([pscustomobject]@{
            organization = 'contoso-tf'; workspacePrefix = 'contoso'
        }) -Force
    $hcpConfig | ConvertTo-Json -Depth 40 | Set-Content $hcpPath -Encoding utf8
    $null = Invoke-LzRender -ConfigPath $hcpPath -OutputDirectory $outHcp -Quiet

    $hcpLayers = @(Get-ChildItem (Join-Path $outHcp 'terraform/live') -Directory)
    foreach ($layerDir in $hcpLayers) {
        $backend = Get-Content (Join-Path $layerDir.FullName 'backend.tf') -Raw
        ok "$($layerDir.Name) uses the cloud block" ($backend -match '(?s)terraform\s*\{\s*cloud\s*\{')
        ok "$($layerDir.Name) gets its own workspace" ($backend -match "name\s*=\s*`"contoso-$($layerDir.Name)`"")
        # Sharing one workspace across layers is the failure this asserts against.
        ok "$($layerDir.Name) has no azurerm partial config" (-not (Test-Path (Join-Path $layerDir.FullName 'backend.hcl')))
    }
    ok 'the organization is emitted once per layer' `
    (@($hcpLayers | Where-Object { (Get-Content (Join-Path $_.FullName 'backend.tf') -Raw) -match 'organization\s*=\s*"contoso-tf"' }).Count -eq $hcpLayers.Count)

    $hcpPlan = Get-Content (Join-Path $outHcp '.github/workflows/terraform-plan.yml') -Raw
    $hcpApply = Get-Content (Join-Path $outHcp '.github/workflows/terraform-apply.yml') -Raw
    ok 'init drops the azurerm partial config' ($hcpPlan -notmatch 'backend-config=backend\.hcl')
    ok 'the CLI gets a workspace token' ($hcpPlan -match 'cli_config_credentials_token:\s*\$\{\{\s*secrets\.TF_API_TOKEN\s*\}\}')
    # The reason state-only is a const and not a preference.
    ok 'the plan destroy gate survives' ($hcpPlan -match 'terraform plan -input=false -no-color -out=tfplan' -and $hcpPlan -match 'terraform show -json tfplan')
    ok 'the apply destroy gate survives' ($hcpApply -match '-out=tfplan' -and $hcpApply -match 'terraform show -json tfplan')
    # Azure auth is untouched: TFC never holds a credential to the tenant.
    ok 'azure login is still OIDC' ($hcpPlan -match 'azure/login' -and $hcpPlan -match 'id-token:\s*write')
    ok 'no azure credential is emitted' ($hcpPlan -notmatch 'client-secret|AZURE_CLIENT_SECRET')
    # state-hardening hardens a storage account this backend does not create.
    ok 'state-hardening is not emitted under TFC' (-not (Test-Path (Join-Path $outHcp 'terraform/live/state-hardening')))

    # The CROSS-LAYER read, which is a different thing from where this layer
    # writes its own state. Until 2026-08-31 the global layer wrote every
    # layer's state to HCP and then read platform-management's state back out
    # of an Azure storage account it had never written to. `terraform validate`
    # does not resolve data sources, so the hcp-config CI leg passed while the
    # estate could not have planned.
    $hcpGlobal = Get-Content (Join-Path $outHcp 'terraform/live/global/main.tf') -Raw
    ok 'the management state is read as a workspace, not a blob' ($hcpGlobal -match '(?s)data "terraform_remote_state" "management".*?backend\s*=\s*"remote"')
    ok 'no azurerm state read survives under TFC' ($hcpGlobal -notmatch '(?s)data "terraform_remote_state" "management".*?backend\s*=\s*"azurerm"')
    # One naming rule in two places that must never disagree: the workspace this
    # reads is the one backend-cloud.tf writes for that layer.
    $hcpMgmtBackend = Get-Content (Join-Path $outHcp 'terraform/live/platform-management/backend.tf') -Raw
    ok 'it names the workspace that layer actually writes' (
        ($hcpMgmtBackend -match 'name\s*=\s*"(?<w>[^"]+)"') -and
        ($hcpGlobal -match ('name\s*=\s*"' + [regex]::Escape($Matches.w) + '"')))
    # Emitting these would name a state location this estate does not use, and
    # the schema does not require backend.azurerm at all under hcp-terraform.
    $hcpTfvars = Get-Content (Join-Path $outHcp 'terraform/live/global/terraform.auto.tfvars') -Raw
    ok 'no azure state coordinates are emitted under TFC' ($hcpTfvars -notmatch 'state_storage_account_name|state_resource_group_name|state_container_name')
}
finally {
    Remove-Item -Recurse -Force $outHcp -ErrorAction SilentlyContinue
    Remove-Item -Force $hcpPath -ErrorAction SilentlyContinue
}

# The azurerm path must be untouched by any of this.
ok 'azurerm still emits an empty backend block' ((Get-Content (Join-Path $out 'terraform/live/global/backend.tf') -Raw) -match 'backend "azurerm" \{\}')
ok 'azurerm still emits backend.hcl'            (Test-Path (Join-Path $out 'terraform/live/global/backend.hcl'))
ok 'azurerm init still supplies it'             ((Get-Content (Join-Path $out '.github/workflows/terraform-plan.yml') -Raw) -match 'backend-config=backend\.hcl')
ok 'azurerm carries no workspace token'         ((Get-Content (Join-Path $out '.github/workflows/terraform-plan.yml') -Raw) -notmatch 'cli_config_credentials_token')
$azGlobal = Get-Content (Join-Path $out 'terraform/live/global/main.tf') -Raw
ok 'azurerm still reads management state from the blob' ($azGlobal -match '(?s)data "terraform_remote_state" "management".*?backend\s*=\s*"azurerm"')
ok 'azurerm still emits its state coordinates' ((Get-Content (Join-Path $out 'terraform/live/global/terraform.auto.tfvars') -Raw) -match 'state_storage_account_name')

# Guards: the combinations that cannot work.
$hcpGuard = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
$hcpGuard.backend.type = 'hcp-terraform'
$hcpGuard.backend | Add-Member -NotePropertyName hcpTerraform -NotePropertyValue ([pscustomobject]@{ organization = '' }) -Force
$g = @((Test-LzRenderGuards -Config $hcpGuard).Violations | Where-Object { $_.Id -eq 'G17' })
ok 'G17 catches a missing organization' (@($g | Where-Object { $_.Message -match 'no organization' }).Count -eq 1)
$hcpGuard.backend.hcpTerraform = [pscustomobject]@{ organization = 'contoso-tf'; executionMode = 'remote' }
$g = @((Test-LzRenderGuards -Config $hcpGuard).Violations | Where-Object { $_.Id -eq 'G17' })
ok 'G17 refuses remote execution' (@($g | Where-Object { $_.Message -match 'execution mode' }).Count -eq 1)
$hcpGuard.backend.hcpTerraform = [pscustomobject]@{ organization = 'contoso-tf' }
$hcpGuard.backend.azurerm | Add-Member -NotePropertyName privateEndpoint -NotePropertyValue ([pscustomobject]@{ enabled = $true }) -Force
$g = @((Test-LzRenderGuards -Config $hcpGuard).Violations | Where-Object { $_.Id -eq 'G17' })
ok 'G17 refuses state hardening under TFC' (@($g | Where-Object { $_.Message -match 'privateEndpoint' }).Count -eq 1)

Write-Host "`n== 12f. caf-minimal is a different hierarchy (TODO 6.4a) ==" -ForegroundColor Cyan
# For a year caf-minimal and caf-standard rendered byte-identical Terraform: the
# architecture was the pinned library's `alz` either way. The schema described a
# trim that never happened and the estimator costed a hierarchy that was never
# deployed. THE ASSERTION THAT MATTERS IS THAT THEY DIFFER — a test checking
# only that each renders something would have passed throughout.
$minPath = Join-Path ([IO.Path]::GetTempPath()) "lz-min-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
$outMin = Join-Path ([IO.Path]::GetTempPath()) "lz-render-min-$([guid]::NewGuid().ToString('n').Substring(0,8))"
$outStd = Join-Path ([IO.Path]::GetTempPath()) "lz-render-std-$([guid]::NewGuid().ToString('n').Substring(0,8))"
try {
    $minConfig = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
    $minConfig.azure.managementGroups.strategy = 'caf-minimal'
    # No Sandbox group means no home for a sandbox subscription (G31). Add-Member
    # rather than assignment: optional slots are STRIPPED from an exported
    # configuration rather than emitted empty, so sample-config.json has no
    # sandbox property to assign to.
    $minConfig.azure.subscriptions | Add-Member -NotePropertyName sandbox -NotePropertyValue '' -Force
    $minConfig | ConvertTo-Json -Depth 40 | Set-Content $minPath -Encoding utf8

    $null = Invoke-LzRender -ConfigPath $minPath -OutputDirectory $outMin -Quiet
    $null = Invoke-LzRender -ConfigPath "$PSScriptRoot/fixtures/sample-config.json" -OutputDirectory $outStd -Quiet

    $minMain = Get-Content (Join-Path $outMin 'terraform/live/global/main.tf') -Raw
    $stdMain = Get-Content (Join-Path $outStd 'terraform/live/global/main.tf') -Raw
    ok 'caf-minimal no longer renders identically to caf-standard' ($minMain -ne $stdMain)

    # Exactly two groups, and exactly which two. "Fewer than standard" would
    # pass for a trim that stranded workloadPlacement.
    $defs = @(Get-ChildItem (Join-Path $outMin 'terraform/live/global/lib/architecture_definitions') -File -ErrorAction SilentlyContinue)
    ok 'caf-minimal emits its own architecture definition' ($defs.Count -eq 1)
    $arch = Get-Content $defs[0].FullName -Raw | ConvertFrom-Json -Depth 20
    $minIds = @($arch.management_groups | ForEach-Object { [string]$_.id } | Sort-Object)
    ok 'it drops exactly sandbox and decommissioned' (
        ($minIds -notcontains 'sandbox') -and ($minIds -notcontains 'decommissioned') -and $minIds.Count -eq 10) ($minIds -join ',')
    # The reason those two and not others: everything else is Platform, Landing
    # Zones, or a child of one, and workloadPlacement targets corp/online.
    ok 'the landing-zone groups workloadPlacement needs survive' (
        ($minIds -contains 'corp') -and ($minIds -contains 'online') -and ($minIds -contains 'landingzones'))
    ok 'no emitted group parents to a dropped one' (
        @($arch.management_groups | Where-Object { $_.parent_id -in @('sandbox','decommissioned') }).Count -eq 0)

    # caf-standard emits none: its architecture IS the library's.
    ok 'caf-standard still selects the library architecture' (
        -not (Test-Path (Join-Path $outStd 'terraform/live/global/lib')))

    # A tfvars naming a group this estate never creates is the failure G31 is
    # the backstop for; under caf-minimal the line must simply not be there.
    $minVars = Get-Content (Join-Path $outMin 'terraform/live/global/terraform.auto.tfvars') -Raw
    ok 'no sandbox placement target is emitted' ($minVars -notmatch 'sandbox_management_group_id')
    ok 'caf-standard still emits one' ((Get-Content (Join-Path $outStd 'terraform/live/global/terraform.auto.tfvars') -Raw) -match 'sandbox_management_group_id')

    # The generated governance doc must describe the estate this client
    # actually gets. hasCustomArchitecture answers "is a local architecture
    # definition emitted", which is true for BOTH departures from the library —
    # but they depart in opposite ways, and gating the "your groups are
    # renamed" narrative on the emit flag told a caf-minimal client something
    # untrue about their own estate. Copilot's review of #127 caught it.
    $minGov = Get-Content (Join-Path $outMin 'docs/governance.md') -Raw
    $stdGov = Get-Content (Join-Path $outStd 'docs/governance.md') -Raw
    ok 'caf-minimal is not told its groups were renamed' ($minGov -notmatch 'uses its own names')
    ok 'caf-minimal is told which groups are missing' (
        $minGov -match 'Sandbox and Decommissioned' -and $minGov -match 'not\s+\*\*created\*\*|\*\*not\s+created\*\*')
    ok 'and the dropped groups read as prose, not JSON' ($minGov -notmatch '\["sandbox"')
    ok 'caf-standard says nothing about a local definition' (
        $stdGov -match 'the library.s own names' -and $stdGov -notmatch 'uses its own names')

    # The renamed case must keep its own narrative, and must NOT claim a trim:
    # custom renames all twelve groups and drops none.
    $custPath = Join-Path ([IO.Path]::GetTempPath()) "lz-cust-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
    $outCust = Join-Path ([IO.Path]::GetTempPath()) "lz-render-cust-$([guid]::NewGuid().ToString('n').Substring(0,8))"
    try {
        Copy-Item "$PSScriptRoot/fixtures/custom-hierarchy-config.json" $custPath
        $null = Invoke-LzRender -ConfigPath $custPath -OutputDirectory $outCust -Quiet
        $custGov = Get-Content (Join-Path $outCust 'docs/governance.md') -Raw
        ok 'custom still gets the renamed narrative' ($custGov -match 'uses its own names')
        ok 'and is not told any group was dropped' ($custGov -notmatch 'not \*\*created\*\*')
    }
    finally {
        Remove-Item -Recurse -Force $outCust -ErrorAction SilentlyContinue
        Remove-Item -Force $custPath -ErrorAction SilentlyContinue
    }

    # G31: caf-minimal + a populated sandbox slot. active_placements filters
    # EMPTY subscription ids, not missing management groups, so without this the
    # failure lands mid-apply against immutable management-group ids.
    $g31Config = Get-Content $minPath -Raw | ConvertFrom-Json -Depth 40
    $g31Config.azure.subscriptions | Add-Member -NotePropertyName sandbox -NotePropertyValue '11111111-1111-1111-1111-111111111111' -Force
    $g31 = @((Test-LzRenderGuards -Config $g31Config).Violations | Where-Object { $_.Id -eq 'G31' })
    ok 'G31 blocks a sandbox subscription under caf-minimal' ($g31.Count -eq 1 -and $g31[0].Severity -eq 'Block')
    ok 'G31 stays quiet when the slot is empty' (
        @((Test-LzRenderGuards -Config $minConfig).Violations | Where-Object { $_.Id -eq 'G31' }).Count -eq 0)
    # caf-standard creates Sandbox, so the same subscription is fine there.
    $stdSandbox = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 40
    $stdSandbox.azure.subscriptions | Add-Member -NotePropertyName sandbox -NotePropertyValue '11111111-1111-1111-1111-111111111111' -Force
    ok 'G31 does not fire under caf-standard' (
        @((Test-LzRenderGuards -Config $stdSandbox).Violations | Where-Object { $_.Id -eq 'G31' }).Count -eq 0)
}
finally {
    Remove-Item -Recurse -Force $outMin, $outStd -ErrorAction SilentlyContinue
    Remove-Item -Force $minPath -ErrorAction SilentlyContinue
}

Write-Host "`n== 13. Schema drift check ==" -ForegroundColor Cyan
$drift = Test-LzSchemaDrift -SchemaPath "$repo/factory/schema/lz-config.schema.json" -MappingPath "$repo/factory/renderer/variable-map.json" -TemplateRoot "$repo/factory/templates"
ok 'wizard and corpus in sync'      ($drift.InSync) (($drift.Findings | Select-Object -First 3 | ForEach-Object { $_.Detail }) -join '; ')

Remove-Item -Recurse -Force $out, $outVwan -ErrorAction SilentlyContinue

Write-Host "`n== Results: $script:pass passed, $script:fail failed ==" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 }
