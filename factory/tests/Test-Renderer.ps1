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
ok 'global supplies twelve policy default values' ($pdvKeys.Count -eq 12) ($pdvKeys -join ',')
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
ok 'answer record round-trips'      ("$($answerRecord.schemaVersion)" -eq '2.2.0')
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

Write-Host "`n== 13. Schema drift check ==" -ForegroundColor Cyan
$drift = Test-LzSchemaDrift -SchemaPath "$repo/factory/schema/lz-config.schema.json" -MappingPath "$repo/factory/renderer/variable-map.json" -TemplateRoot "$repo/factory/templates"
ok 'wizard and corpus in sync'      ($drift.InSync) (($drift.Findings | Select-Object -First 3 | ForEach-Object { $_.Detail }) -join '; ')

Remove-Item -Recurse -Force $out, $outVwan -ErrorAction SilentlyContinue

Write-Host "`n== Results: $script:pass passed, $script:fail failed ==" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 }
