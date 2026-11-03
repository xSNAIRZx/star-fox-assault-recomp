# PSScriptAnalyzer settings for the launcher and host tools.
#
# From the repository root:
#   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./tools/PSScriptAnalyzerSettings.psd1
#
# Error-severity findings are never excluded. The rules below are excluded because
# they describe a design decision rather than a defect:
#
#   PSAvoidUsingWriteHost                        The launcher and build workers report
#                                                progress on the console window they
#                                                own; no pipeline consumer reads it.
#   PSUseShouldProcessForStateChangingFunctions  These are internal helpers called
#                                                from the launcher, not exported cmdlets.
#   PSUseSingularNouns, PSUseApprovedVerbs       Helper names follow the launcher's own
#                                                vocabulary (Get-BackupMetadata,
#                                                Quote-Argument) and are not public API.
#   PSReviewUnusedParameter                      Parameters such as -CancelFile and
#                                                -Offline are consumed by nested
#                                                functions in the same script.
#   PSAvoidUsingEmptyCatchBlock                  Best-effort paths where a stale or
#                                                unreadable file must fall back to a
#                                                documented default instead of aborting.
#   PSAvoidAssignmentToAutomaticVariable         The remaining hits are WinForms event
#                                                handler parameters named $sender and $e.
#                                                The real collisions on $args and $input
#                                                were fixed; run without -Settings to see
#                                                every finding, including this rule.
@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'
        'PSUseApprovedVerbs'
        'PSReviewUnusedParameter'
        'PSAvoidUsingEmptyCatchBlock'
        'PSAvoidAssignmentToAutomaticVariable'
    )
}
