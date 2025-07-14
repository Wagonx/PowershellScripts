# Location Server Mirror Script
param(
    [Parameter(Mandatory=$true)]
    [string]$LocationServer,
    [string]$LogDirectory = "C:\logs",
    [string]$OpsGenieApiKey
)

# Extract location number and build paths
$LocationNumber = $LocationServer -replace 'server$'
$Paths = @{
    SourceShare      = "\\$LocationServer\share\"
    SourceProfile    = "\\$LocationServer\profiledata$\"
    DestShare        = "\\archive\g$\$LocationNumber\share\"
    DestProfile      = "\\archive\g$\$LocationNumber\Profiledata\"
}

# Create log directory and generate timestamps
if (!(Test-Path $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Validate all paths exist
$MissingPaths = $Paths.GetEnumerator() | Where-Object { !(Test-Path $_.Value) } | ForEach-Object { "$($_.Key): $($_.Value)" }
if ($MissingPaths) {
    $ErrorLog = Join-Path $LogDirectory "robocopy-$LocationNumber-error-$TimeStamp.log"
    $ErrorMsg = "Path validation failed:`n$($MissingPaths -join "`n")"
    $ErrorMsg | Out-File $ErrorLog -Encoding UTF8
    
    if ($OpsGenieApiKey) {
        try {
            Send-OpsGenieAlert -ApiKey $OpsGenieApiKey -Message "Location $LocationNumber mirror CRITICAL - Path validation failed" `
                -Description "Mirror operation failed for $LocationServer`n`n$ErrorMsg`n`nLogged to: $ErrorLog" `
                -Responders @("team:Operations", "team:Infrastructure") -Tags @("mirror-critical", "location-$LocationNumber", "path-validation") -Priority "P1"
        } catch {}
    }
    exit 99
}

# Execute robocopy operations
$Jobs = @(
    @{ Source = $Paths.SourceShare; Dest = $Paths.DestShare; Log = Join-Path $LogDirectory "robocopy-$LocationNumber-share-$TimeStamp.log" }
    @{ Source = $Paths.SourceProfile; Dest = $Paths.DestProfile; Log = Join-Path $LogDirectory "robocopy-$LocationNumber-profile-$TimeStamp.log" }
)

$ExitCodes = $Jobs | ForEach-Object {
    & robocopy $_.Source $_.Dest /MIR /R:5 /W:10 /MT:16 /COPY:DATSOU /SECFIX `
        /XF *.tmp *.temp *~ *.swp *.lock *.log `
        /XD .snapshot temp '$RECYCLE.BIN' 'System Volume Information' `
        /LOG:$_.Log /NP /NDL /NC /BYTES /TS
    $LASTEXITCODE
}

$OverallExitCode = ($ExitCodes | Measure-Object -Maximum).Maximum

# Create summary and send alert
$SummaryLog = Join-Path $LogDirectory "robocopy-$LocationNumber-summary-$TimeStamp.log"
@"
Location Server Mirror Summary - $LocationServer
Date: $(Get-Date)
Location Number: $LocationNumber

Share Mirror Exit Code: $($ExitCodes[0])
Profile Data Mirror Exit Code: $($ExitCodes[1])
Overall Exit Code: $OverallExitCode

Log Files:
- Share: $($Jobs[0].Log)
- Profile: $($Jobs[1].Log)
"@ | Out-File $SummaryLog -Encoding UTF8

if ($OpsGenieApiKey) {
    try {
        $AlertType, $Priority, $Responders = switch ($OverallExitCode) {
            {$_ -in 0..1} { "INFO", "P5", @("team:Operations") }
            {$_ -in 2..7} { "WARNING", "P3", @("team:Operations", "team:Infrastructure") }
            default       { "ERROR", "P1", @("team:Operations", "team:Infrastructure") }
        }
        
        Send-OpsGenieAlert -ApiKey $OpsGenieApiKey -Message "Location $LocationNumber mirror $AlertType - Exit Code $OverallExitCode" `
            -Description "Location Server: $LocationServer`nDate: $(Get-Date)`n`nShare Exit Code: $($ExitCodes[0])`nProfile Exit Code: $($ExitCodes[1])`nOverall Exit Code: $OverallExitCode`n`nLog Files: $SummaryLog" `
            -Responders $Responders -Tags @("mirror-$($AlertType.ToLower())", "location-$LocationNumber", "robocopy", "exit-code-$OverallExitCode") -Priority $Priority
            
        Add-Content $SummaryLog "`nOpsGenie $AlertType alert sent - Priority: $Priority"
    }
    catch {
        Add-Content $SummaryLog "`nFailed to send OpsGenie alert: $_"
    }
}

exit $OverallExitCode
