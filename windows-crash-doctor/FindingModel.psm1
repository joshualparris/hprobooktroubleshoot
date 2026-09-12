Set-StrictMode -Version Latest

$script:CrashDoctorSeverityOrder = @{
    Critical = 0
    High     = 1
    Medium   = 2
    Low      = 3
    Info     = 4
}

function New-CrashDoctorFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [ValidateSet('High', 'Medium', 'Low')]
        [string]$Confidence,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Evidence,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Interpretation,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NextStep
    )

    return [pscustomobject][ordered]@{
        Id             = $Id
        Severity       = $Severity
        Confidence     = $Confidence
        Title          = $Title
        Evidence       = $Evidence
        Interpretation = $Interpretation
        NextStep       = $NextStep
    }
}

function Sort-CrashDoctorFindings {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Findings = @()
    )

    foreach ($finding in @($Findings)) {
        if ($null -eq $finding) {
            throw 'A Crash Doctor finding cannot be null.'
        }
        foreach ($requiredProperty in @('Id', 'Severity', 'Confidence', 'Title', 'Evidence', 'Interpretation', 'NextStep')) {
            if ($null -eq $finding.PSObject.Properties[$requiredProperty]) {
                throw "Crash Doctor finding is missing required property '$requiredProperty'."
            }
        }
        if (-not $script:CrashDoctorSeverityOrder.ContainsKey([string]$finding.Severity)) {
            throw "Crash Doctor finding '$($finding.Id)' has unsupported severity '$($finding.Severity)'."
        }
    }

    return @(
        @($Findings) |
            Sort-Object @{ Expression = { $script:CrashDoctorSeverityOrder[[string]$_.Severity] } }, @{ Expression = { [string]$_.Id } }
    )
}

Export-ModuleMember -Function New-CrashDoctorFinding, Sort-CrashDoctorFindings
