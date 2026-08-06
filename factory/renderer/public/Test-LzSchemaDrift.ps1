#Requires -Version 7.0
<#
    Schema ↔ Terraform variable drift detection.

    This is the mechanism that fixes the defect already recorded in TODO.md:
    the static generator offers 47 policy toggles that were never reconciled
    against what terraform/modules/policy-baseline actually implements.

    The failure it prevents is quiet. A wizard option with no corresponding
    Terraform variable produces a .tfvars entry Terraform ignores — the operator
    sets "enable X", the plan succeeds, and X is never deployed. Nothing in the
    pipeline reports a problem, because from Terraform's point of view nothing
    is wrong.

    Two directions are checked, and both matter:

      Orphaned config  — a mapped config key with no matching Terraform variable.
                         Symptom: the setting silently does nothing.
      Unmapped variable — a required Terraform variable no config key feeds.
                         Symptom: apply prompts for input, or fails in CI.
#>

Set-StrictMode -Version Latest

function Get-LzTerraformVariables {
    <#
    .SYNOPSIS
        Parse variable declarations from a Terraform variables file.
    .DESCRIPTION
        A deliberately small HCL reader: it extracts the variable name, whether
        a default exists, and the declared type. Using a real HCL parser would
        mean taking a dependency the factory does not otherwise need, and the
        subset of syntax that appears in a variables.tf is stable enough that
        this is reliable.
    .OUTPUTS
        Objects with Name, HasDefault, Type, File.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return @() }

    $content = Get-Content $Path -Raw
    $results = @()

    # Match: variable "name" { ... } with brace balancing so a nested object
    # type does not terminate the block early.
    $variableBlocks = [regex]::Matches($content, 'variable\s+"(?<name>[^"]+)"\s*\{')
    foreach ($m in $variableBlocks) {
        $name = $m.Groups['name'].Value
        $start = $m.Index + $m.Length
        $depth = 1
        $i = $start
        while ($i -lt $content.Length -and $depth -gt 0) {
            if ($content[$i] -eq '{') { $depth++ }
            elseif ($content[$i] -eq '}') { $depth-- }
            $i++
        }
        $body = $content.Substring($start, [Math]::Max(0, $i - $start - 1))

        $type = ''
        if ($body -match '(?m)^\s*type\s*=\s*(?<t>.+?)\s*$') { $type = $Matches['t'].Trim() }

        # Validation regexes matter as much as the variable's existence. A
        # variable that exists but rejects the value the wizard produces fails
        # at plan time, after the operator believes configuration is complete.
        $validationRegex = ''
        if ($body -match 'can\(\s*regex\(\s*"(?<re>(?:[^"\\]|\\.)*)"') { $validationRegex = $Matches['re'] }

        # Enum-style validations are the other half of constraint compatibility,
        # and the regex reader above is blind to them. A schema enum offering a
        # value that `contains([...])` rejects renders cleanly and then fails at
        # plan time — the azfw `Basic` defect class.
        #
        # The list is bound to `var.<thisName>` deliberately. A variables file
        # also contains negated membership tests over collection elements, e.g.
        #   for r in var.management_ip_ranges : !contains(["*", "0.0.0.0/0"], r)
        # where the bracketed list is a DENY list over `r`, not the set of
        # allowed values for the variable. Requiring the `, var.<name>)` tail
        # excludes those instead of inverting their meaning.
        $validationAllowedValues = @()
        $containsPattern = 'contains\(\s*\[(?<list>[^\]]*)\]\s*,\s*var\.{0}\s*\)' -f [regex]::Escape($name)
        $containsMatch = [regex]::Match($body, $containsPattern)
        if ($containsMatch.Success) {
            $validationAllowedValues = @(
                [regex]::Matches($containsMatch.Groups['list'].Value, '"(?<v>(?:[^"\\]|\\.)*)"') |
                    ForEach-Object { $_.Groups['v'].Value }
            )
        }

        $results += [pscustomobject]@{
            Name                    = $name
            HasDefault              = [bool]($body -match '(?m)^\s*default\s*=')
            Type                    = $type
            ValidationRegex         = $validationRegex
            ValidationAllowedValues = $validationAllowedValues
            File                    = $Path
        }
    }
    return $results
}

function Test-LzSchemaDrift {
    <#
    .SYNOPSIS
        Compare the configuration schema against the Terraform variables the
        template corpus declares.
    .PARAMETER SchemaPath
        factory/schema/lz-config.schema.json
    .PARAMETER MappingPath
        factory/renderer/variable-map.json — the declared correspondence between
        config keys and Terraform variables, per layer.
    .PARAMETER TemplateRoot
        Root of the template corpus containing the layers.
    .OUTPUTS
        Object with Findings, DriftCount, InSync.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$MappingPath,
        [Parameter(Mandatory)][string]$TemplateRoot
    )

    $findings = @()

    if (-not (Test-Path $SchemaPath))  { throw "Schema not found: $SchemaPath" }
    if (-not (Test-Path $MappingPath)) { throw "Variable map not found: $MappingPath" }

    $schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json -Depth 30
    $mapping = Get-Content $MappingPath -Raw | ConvertFrom-Json -Depth 20

    $schemaPaths = @()
    Get-LzSchemaPaths -Node $schema -Prefix '' -Accumulator ([ref]$schemaPaths)

    foreach ($layer in $mapping.layers.PSObject.Properties) {
        $layerName = $layer.Name
        $layerDef = $layer.Value

        $varsPath = Join-Path $TemplateRoot $layerDef.variablesFile
        $declared = Get-LzTerraformVariables -Path $varsPath

        if (-not (Test-Path $varsPath)) {
            $findings += [pscustomobject]@{
                Layer = $layerName; Kind = 'MissingVariablesFile'
                Detail = "Declared variables file does not exist: $($layerDef.variablesFile)"
                Severity = 'Block'
            }
            continue
        }

        $declaredNames = @($declared | ForEach-Object { $_.Name })
        $mappedVars = @()

        foreach ($entry in $layerDef.variables.PSObject.Properties) {
            $tfVar = $entry.Name
            $configPath = $entry.Value
            $mappedVars += $tfVar

            # Direction 1: the Terraform variable must exist.
            if ($tfVar -notin $declaredNames) {
                $findings += [pscustomobject]@{
                    Layer = $layerName; Kind = 'OrphanedConfigKey'
                    Detail = "Config key '$configPath' maps to Terraform variable '$tfVar', which is not declared in $($layerDef.variablesFile). The setting would silently do nothing."
                    Severity = 'Block'
                }
            }

            # Direction 2: the config path must exist in the schema. `computed.`
            # paths are renderer-derived and legitimately absent from the schema.
            if ($configPath -notlike 'computed.*' -and $configPath -notlike 'literal:*') {
                $normalized = ($configPath -replace '\[\d+\]', '')
                if ($normalized -notin $schemaPaths) {
                    $findings += [pscustomobject]@{
                        Layer = $layerName; Kind = 'UnknownConfigPath'
                        Detail = "Terraform variable '$tfVar' maps to config path '$configPath', which does not exist in the schema."
                        Severity = 'Block'
                    }
                }
                else {
                    # Direction 2b: constraint compatibility. Existence is not
                    # enough — if Terraform's validation regex rejects values the
                    # schema accepts, the wizard can produce a configuration that
                    # renders cleanly and then fails at plan time.
                    $decl = @($declared | Where-Object { $_.Name -eq $tfVar })
                    if ($decl.Count -gt 0 -and $decl[0].ValidationRegex) {
                        $schemaPattern = Get-LzSchemaPattern -Schema $schema -Path $normalized
                        if ($schemaPattern) {
                            $counter = Get-LzConstraintCounterexample `
                                -SchemaPattern $schemaPattern -TerraformPattern $decl[0].ValidationRegex
                            if ($counter) {
                                $findings += [pscustomobject]@{
                                    Layer = $layerName; Kind = 'ConstraintMismatch'
                                    Detail = "Schema allows values for '$configPath' that Terraform variable '$tfVar' rejects. Schema pattern '$schemaPattern' vs Terraform validation '$($decl[0].ValidationRegex)'. Counterexample: '$counter' passes the wizard but fails terraform plan."
                                    Severity = 'Block'
                                }
                            }
                        }
                    }

                    # Direction 2c: enum compatibility. Same failure as 2b, but
                    # for discrete value sets, which the regex comparison cannot
                    # see at all. Unlike regex equivalence this is decidable —
                    # it is a set difference — so every offending value is
                    # reported, not just one counterexample.
                    if ($decl.Count -gt 0 -and $decl[0].ValidationAllowedValues.Count -gt 0) {
                        $schemaEnum = Get-LzSchemaEnum -Schema $schema -Path $normalized
                        if ($schemaEnum -and $schemaEnum.Count -gt 0) {
                            $rejected = @($schemaEnum | Where-Object { $_ -cnotin $decl[0].ValidationAllowedValues })
                            if ($rejected.Count -gt 0) {
                                $findings += [pscustomobject]@{
                                    Layer = $layerName; Kind = 'ConstraintMismatch'
                                    Detail = "Schema enum for '$configPath' offers value(s) [$($rejected -join ', ')] that Terraform variable '$tfVar' rejects. Terraform accepts [$($decl[0].ValidationAllowedValues -join ', ')]. Selecting a rejected value in the wizard renders cleanly and then fails terraform plan."
                                    Severity = 'Block'
                                }
                            }
                        }
                    }
                }
            }
        }

        # Direction 3: a required variable (no default) that nothing feeds will
        # stall apply waiting for input.
        foreach ($d in $declared) {
            if (-not $d.HasDefault -and $d.Name -notin $mappedVars) {
                $findings += [pscustomobject]@{
                    Layer = $layerName; Kind = 'UnmappedRequiredVariable'
                    Detail = "Terraform variable '$($d.Name)' in $($layerDef.variablesFile) has no default and no config key supplies it. Apply would prompt for input, or fail in CI."
                    Severity = 'Block'
                }
            }
        }

        # Optional variables with no mapping are fine, but worth surfacing:
        # they are usually either dead or an unexposed feature.
        foreach ($d in $declared) {
            if ($d.HasDefault -and $d.Name -notin $mappedVars) {
                $findings += [pscustomobject]@{
                    Layer = $layerName; Kind = 'UnexposedOptionalVariable'
                    Detail = "Terraform variable '$($d.Name)' has a default and is not exposed by the wizard. Confirm the default is the intended value."
                    Severity = 'Info'
                }
            }
        }
    }

    $blocking = @($findings | Where-Object { $_.Severity -eq 'Block' })

    [pscustomobject]@{
        Findings   = $findings
        DriftCount = $blocking.Count
        InfoCount  = @($findings | Where-Object { $_.Severity -eq 'Info' }).Count
        InSync     = ($blocking.Count -eq 0)
    }
}

function Get-LzSchemaPattern {
    <#
    .SYNOPSIS
        Retrieve the `pattern` constraint declared for a schema path, if any.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Schema,
        [Parameter(Mandatory)][string]$Path
    )

    $node = $Schema
    foreach ($segment in ($Path -split '\.')) {
        # Parenthesised: without the parentheses, -not binds to the name list
        # first and the guard never fires, so a path with no `properties` node
        # throws under StrictMode instead of returning $null.
        if (-not ($node.PSObject.Properties.Name -contains 'properties')) { return $null }
        if (-not ($node.properties.PSObject.Properties.Name -contains $segment)) { return $null }
        $node = $node.properties.$segment
    }

    # Resolve a $ref into $defs so shared definitions carry their constraints.
    if ($node.PSObject.Properties.Name -contains '$ref') {
        $refName = ($node.'$ref' -replace '^#/\$defs/', '')
        if ($Schema.PSObject.Properties.Name -contains '$defs' -and
            $Schema.'$defs'.PSObject.Properties.Name -contains $refName) {
            $node = $Schema.'$defs'.$refName
        }
    }

    if ($node.PSObject.Properties.Name -contains 'pattern') { return $node.pattern }
    return $null
}

function Get-LzSchemaEnum {
    <#
    .SYNOPSIS
        Retrieve the `enum` constraint declared for a schema path, if any.
    .DESCRIPTION
        Deliberately mirrors Get-LzSchemaPattern, including the $ref resolution
        into $defs, so enum-constrained and pattern-constrained paths are read
        the same way. Kept as a sibling rather than folded into one accessor
        because Get-LzSchemaPattern is exported and unit-tested against its
        current signature.
    .OUTPUTS
        The array of permitted values, or $null when the path declares no enum.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Schema,
        [Parameter(Mandatory)][string]$Path
    )

    $node = $Schema
    foreach ($segment in ($Path -split '\.')) {
        if (-not ($node.PSObject.Properties.Name -contains 'properties')) { return $null }
        if (-not ($node.properties.PSObject.Properties.Name -contains $segment)) { return $null }
        $node = $node.properties.$segment
    }

    if ($node.PSObject.Properties.Name -contains '$ref') {
        $refName = ($node.'$ref' -replace '^#/\$defs/', '')
        if ($Schema.PSObject.Properties.Name -contains '$defs' -and
            $Schema.'$defs'.PSObject.Properties.Name -contains $refName) {
            $node = $Schema.'$defs'.$refName
        }
    }

    # An array-typed config key constrains its ELEMENTS, so the enum that a
    # per-element `contains()` validation must agree with lives under `items`.
    if ($node.PSObject.Properties.Name -contains 'items' -and
        -not ($node.PSObject.Properties.Name -contains 'enum')) {
        $node = $node.items
    }

    if ($node.PSObject.Properties.Name -contains 'enum') { return @($node.enum) }
    return $null
}

function Get-LzConstraintCounterexample {
    <#
    .SYNOPSIS
        Find a value the schema accepts but Terraform's validation rejects.
    .DESCRIPTION
        Regex equivalence is undecidable in general, so this does not attempt it.
        It generates candidate strings from the schema pattern when that pattern
        has the simple, overwhelmingly common shape ^[class]{min,max}$, then
        tests each against the Terraform regex. The first string the schema
        accepts and Terraform rejects is returned as a concrete counterexample.

        Returning a real counterexample rather than "these regexes differ"
        matters: it turns an argument about equivalence into a fact the reader
        can verify in one step.
    .OUTPUTS
        The counterexample string, or $null when none was found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SchemaPattern,
        [Parameter(Mandatory)][string]$TerraformPattern
    )

    if ($SchemaPattern -eq $TerraformPattern) { return $null }

    # Only the simple bounded-character-class shape is analysed.
    if ($SchemaPattern -notmatch '^\^\[(?<class>[^\]]+)\]\{(?<min>\d+),(?<max>\d+)\}\$$') { return $null }

    $class = $Matches['class']
    $min = [int]$Matches['min']
    $max = [int]$Matches['max']

    # Representative characters drawn from the declared class.
    $chars = @()
    if ($class -match 'a-z') { $chars += 'a' }
    if ($class -match 'A-Z') { $chars += 'A' }
    if ($class -match '0-9') { $chars += '0' }
    if ($chars.Count -eq 0) { $chars = @($class[0]) }

    $candidates = @()
    foreach ($len in @($min, [Math]::Min($min + 1, $max), $max)) {
        if ($len -lt 1) { continue }
        foreach ($c in $chars) { $candidates += ($c * $len) }
        # A mixed string exercises the full character class, which catches a
        # Terraform regex that omits digits the schema permits.
        if ($chars.Count -gt 1 -and $len -ge $chars.Count) {
            $mixed = -join (0..($len - 1) | ForEach-Object { $chars[$_ % $chars.Count] })
            $candidates += $mixed
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $schemaAccepts = [bool]([regex]::IsMatch($candidate, $SchemaPattern))
        if (-not $schemaAccepts) { continue }
        $tfAccepts = $false
        try { $tfAccepts = [bool]([regex]::IsMatch($candidate, $TerraformPattern)) } catch { return $null }
        if (-not $tfAccepts) { return $candidate }
    }

    return $null
}

function Get-LzSchemaPaths {
    <#
    .SYNOPSIS
        Enumerate every dotted property path a JSON Schema declares.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Node,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix,
        [Parameter(Mandatory)][ref]$Accumulator
    )

    if (-not ($Node.PSObject.Properties.Name -contains 'properties')) { return }

    foreach ($p in $Node.properties.PSObject.Properties) {
        $path = if ($Prefix) { "$Prefix.$($p.Name)" } else { $p.Name }
        $Accumulator.Value += $path

        $child = $p.Value
        if ($child.PSObject.Properties.Name -contains 'properties') {
            Get-LzSchemaPaths -Node $child -Prefix $path -Accumulator $Accumulator
        }
        # Array-of-object item properties are addressable as path.field.
        if ($child.PSObject.Properties.Name -contains 'items' -and
            $child.items.PSObject.Properties.Name -contains 'properties') {
            Get-LzSchemaPaths -Node $child.items -Prefix $path -Accumulator $Accumulator
        }
    }
}
