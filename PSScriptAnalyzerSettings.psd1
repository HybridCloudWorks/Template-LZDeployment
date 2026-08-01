@{
    # Repo-wide PSScriptAnalyzer policy. The VS Code PowerShell extension picks this
    # file up automatically; CI can opt in with:
    #   Invoke-ScriptAnalyzer -Path <file> -Settings ./PSScriptAnalyzerSettings.psd1
    # Every rule not listed below stays active (including
    # PSUseBOMForUnicodeEncodedFile and PSAvoidUsingEmptyCatchBlock).
    ExcludeRules = @(
        # These scripts are deliberately interactive operator consoles with colored output.
        'PSAvoidUsingWriteHost'

        # Established internal function names; renaming is a cross-script break risk.
        'PSUseSingularNouns'
        'PSUseApprovedVerbs'

        # Scripts gate destructive actions with their own explicit prompts (e.g. "Type 'CREATE'").
        'PSUseShouldProcessForStateChangingFunctions'

        # Advisory noise on hook/param patterns.
        'PSReviewUnusedParameter'
    )
}
