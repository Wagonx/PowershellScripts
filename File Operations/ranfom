    <#
    .SYNOPSIS
        This script mirrors dirs from location servers to archive
    .DESCRIPTION
        This script uses RoboCopy to mirror the Share and UserData directory from a location server to offsite NTFS file system. Then reports the status to OpsGenie
    .PARAMETER LocationServer
        Hostname of the location server needing the mirror job
    .PARAMETER LogDirectory
        Root folder where the script will store and organize various logs, default is 'c:\logs\mirror\'
    .PARAMETER OpsGenieApiKEy
        Optional API key to have logs sent to opsgenie
    .PARAMETER RetentionDays
        The integer value for how many days of logs will be kept when the cleanup log function runs, default is 30 days
    .PARAMETER TestMode 
        Switch allowing for a debug mode to be enabled, providing information about exection without actually carrying out any file operations\
    .EXAMPLE
        .\locmirror.ps1 -LocationServer "07server2" -OpsGenieApiKEy "xxxxxxxxx-xxx-xxx-xxxxxx" 
    .NOTES
        Author: Collin Blomberg
    #>

param(
    [Parameter(Mandatory=$true)]
    [string]$LocationServer,
    [string]$LogDirectory = "C:\logs\mirror",
    [string]$OpsGenieApiKey,
    [int]$RetentionDays = 30,
    [switch]$Force,
    [switch]$TestMode
)

$ScriptVersion = "2.1"

# Extract location number (regex for the first 2 digits of hostname)
$LocationNumber = if ($LocationServer -match '^(\d{2})') { $matches[1] } else { 
    throw "Unable to extract location number from hostname '$LocationServer'. Expected format: starts with 2 digits." 
}

# Construct paths from params
$Paths = @{
    SourceShare   = "\\$LocationServer\share\"
    SourceProfile = "\\$LocationServer\profiledata$\"
    DestShare     = "\\archive\g$\$LocationNumber\share\"
    DestProfile   = "\\archive\g$\$LocationNumber\Profiledata\"
}

# Custom Logging Module - Includes Log retention logic
$LocationLogDir = Join-Path $LogDirectory $LocationNumber
if (!(Test-Path $LocationLogDir)) { New-Item -ItemType Directory -Path $LocationLogDir -Force | Out-Null }

$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$MainLogFile = Join-Path $LocationLogDir "mirror-$LocationNumber-$TimeStamp.log"

function Write-MirrorLog {
    param([string]$Message, [string]$Level = "INFO")
    $LogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $LogEntry
    Add-Content -Path $MainLogFile -Value $LogEntry -Encoding UTF8
}

function Send-MirrorAlert {
    param($ExitCode, $Results, $LocationServer, $LocationNumber, $SummaryLog, $TestMode)
    
    if (!$OpsGenieApiKey) { return }
    
    $AlertType, $Priority, $Message = switch ($ExitCode) {
        {$_ -in 0..3} { "SUCCESS", "P5", "completed successfully" }
        {$_ -in 4..7} { "WARNING", "P3", "completed with warnings" }
        default       { "ERROR", "P3", "failed with errors" }
    }
    
    $TestSuffix = if ($TestMode) { " (TEST MODE)" }
    $TestTag = if ($TestMode) { @("test-mode") } else { @() }
    
    try {
        Send-OpsGenieAlert -ApiKey $OpsGenieApiKey `
            -Message "Location $LocationNumber mirror $Message$TestSuffix - Exit Code $ExitCode" `
            -Description "Location Server: $LocationServer`nDate: $(Get-Date)`n$(if ($TestMode) { "*** TEST MODE - No actual file operations performed ***`n`n" })$($Results | ForEach-Object { "$($_.Name) Exit Code: $($_.ExitCode)$(if ($TestMode) { " (TEST)" }) (Duration: $($_.Duration.ToString('hh\:mm\:ss')))" } | Out-String)`nOverall Exit Code: $ExitCode$(if ($TestMode) { " (TEST)" })`n`nSummary Log: $SummaryLog" `
            -Responders @("team:Help Desk") `
            -Tags (@("mirror-$($AlertType.ToLower())", "location-$LocationNumber", "robocopy", "exit-code-$ExitCode") + $TestTag) `
            -Priority $Priority
            
        Write-MirrorLog "OpsGenie $AlertType alert sent - Priority: $Priority" "INFO"
    }
    catch {
        Write-MirrorLog "Failed to send OpsGenie alert: $_" "ERROR"
    }
}

# Intialize logging module
Write-MirrorLog "Starting mirror operation for $LocationServer (Location: $LocationNumber)" "INFO"
Write-MirrorLog "Script Version: $ScriptVersion" "INFO"
if ($TestMode) {
    Write-MirrorLog "*** RUNNING IN TEST MODE - No actual file operations will be performed ***" "INFO"
}

# Start of Pre copy operational checks
Write-MirrorLog "Performing pre-flight checks..." "INFO"

# Logic to prevent duplicate mirror job from executing
if (!$Force -and !$TestMode) {
    $RunningProcesses = Get-Process | Where-Object { $_.ProcessName -eq "robocopy" -and $_.CommandLine -like "*$LocationNumber*" }
    if ($RunningProcesses) {
        Write-MirrorLog "Another mirror operation is running for location $LocationNumber. Use -Force to override." "ERROR"
        exit 98
    }
}

# Path Validation, ensure the destinations exist before starting the robocopy operation and triggering its own alert saying such 
$MissingPaths = $Paths.GetEnumerator() | Where-Object { !(Test-Path $_.Value) } | ForEach-Object { "$($_.Key): $($_.Value)" }
if ($MissingPaths) {
    $ErrorMsg = "Path validation failed:`n$($MissingPaths -join "`n")"
    Write-MirrorLog $ErrorMsg "ERROR"
    
    if ($OpsGenieApiKey) {
        try {
            Send-OpsGenieAlert -ApiKey $OpsGenieApiKey -Message "Location $LocationNumber mirror CRITICAL - Path validation failed" `
                -Description "Mirror operation failed for $LocationServer`n`n$ErrorMsg`n`nLogged to: $MainLogFile" `
                -Responders @("team:Help Desk") -Tags @("mirror-critical", "location-$LocationNumber", "path-validation") -Priority "P3"
            Write-MirrorLog "OpsGenie alert sent for path validation failure" "INFO"
        } catch {
            Write-MirrorLog "Failed to send OpsGenie alert: $_" "ERROR"
        }
    }
    exit 99
}

# Execute RoboCopy operations based on the start switches
Write-MirrorLog "Starting robocopy operations..." "INFO"

$Jobs = @(
    @{ Name = "Share"; Source = $Paths.SourceShare; Dest = $Paths.DestShare; Log = Join-Path $LocationLogDir "robocopy-$LocationNumber-share-$TimeStamp.log" }
    @{ Name = "Profile"; Source = $Paths.SourceProfile; Dest = $Paths.DestProfile; Log = Join-Path $LocationLogDir "robocopy-$LocationNumber-profile-$TimeStamp.log" }
)


$Results = foreach ($Job in $Jobs) {
    Write-MirrorLog "Starting $($Job.Name) mirror: $($Job.Source) -> $($Job.Dest)" "INFO"
    $StartTime = Get-Date
    
    if ($TestMode) {
        Write-MirrorLog "TEST MODE: Running robocopy with /L (list only) flag..." "INFO"
        Write-MirrorLog "DEBUG: Full robocopy command will be:" "INFO"
        Write-MirrorLog "robocopy `"$($Job.Source)`" `"$($Job.Dest)`" /MIR /L /R:3 /W:10 /MT:8 /COPY:DATSOU /SECFIX /XF ... `"/LOG:$($Job.Log)`" /NP /NDL /NC /BYTES /TS /TEE" "INFO"
        
        $ExitCode = & robocopy $Job.Source $Job.Dest /MIR /L /R:3 /W:10 /MT:8 /COPY:COPYALL /SECFIX `
            /XF *.tmp *.temp *~ *.swp *.lock *.log *.pst *.cab Thumbs.db `
            /XD .snapshot temp '$RECYCLE.BIN' 'System Volume Information' HubSpot 'ID Scans' 'My Documents\My Pictures' 'Scanned IDs' 'Scanned ID''s' 'Scanned Id''s Bryan' 'Share\Programs\Fiserv' 'Share\programs\loanproc' 'Share\Programs\patches' 'Share\Replaced Computers' CCCDataBackup ProfileData `
            "/LOG:$($Job.Log)" /NP /NDL /NC /BYTES /TS /TEE
        $ExitCode = $LASTEXITCODE
    } else {        
        $ExitCode = & robocopy $Job.Source $Job.Dest /MIR /R:3 /W:10 /MT:8 /COPY:COPYALL /SECFIX `
            /XF *.tmp *.temp *~ *.swp *.lock *.log *.pst *.cab Thumbs.db `
            /XD .snapshot temp '$RECYCLE.BIN' 'System Volume Information' HubSpot 'ID Scans' 'My Documents\My Pictures' 'Scanned IDs' 'Scanned ID''s' 'Scanned Id''s Bryan' 'Share\Programs\Fiserv' 'Share\programs\loanproc' 'Share\Programs\patches' 'Share\Replaced Computers' CCCDataBackup ProfileData `
            "/LOG:$($Job.Log)" /NP /NDL /NC /BYTES /TS /TEE
        $ExitCode = $LASTEXITCODE
    }
    
    $Duration = (Get-Date) - $StartTime
    $DisplayExitCode = if ($TestMode) { "$ExitCode (TEST)" } else { $ExitCode }
    
    Write-MirrorLog "$($Job.Name) mirror completed with exit code $DisplayExitCode (Duration: $($Duration.ToString('hh\:mm\:ss')))" "INFO"
    
    [PSCustomObject]@{
        Name = $Job.Name
        ExitCode = $ExitCode
        Duration = $Duration
        LogFile = $Job.Log
    }
}

$OverallExitCode = ($Results.ExitCode | Measure-Object -Maximum).Maximum

# Create summary for log end
$SummaryLog = Join-Path $LocationLogDir "summary-$LocationNumber-$TimeStamp.log"
$TestModeHeader = if ($TestMode) { "`n*** TEST MODE - No actual file operations performed ***" }

@"
Location Server Mirror Summary - $LocationServer
Date: $(Get-Date)
Location Number: $LocationNumber
Script Version: $ScriptVersion$TestModeHeader

Results:
$($Results | ForEach-Object { "- $($_.Name): Exit Code $($_.ExitCode)$(if ($TestMode) { " (TEST)" }) (Duration: $($_.Duration.ToString('hh\:mm\:ss')))" } | Out-String)
Overall Exit Code: $OverallExitCode$(if ($TestMode) { " (TEST)" })

Log Files:
$($Results | ForEach-Object { "- $($_.Name): $($_.LogFile)" } | Out-String)
Main Log: $MainLogFile
"@ | Out-File $SummaryLog -Encoding UTF8

Write-MirrorLog "Mirror operation completed. Overall exit code: $OverallExitCode" "INFO"

# Send final result alert and cleanup 
Send-MirrorAlert -ExitCode $OverallExitCode -Results $Results -LocationServer $LocationServer -LocationNumber $LocationNumber -SummaryLog $SummaryLog -TestMode $TestMode

# Clean up old log files
if ($RetentionDays -gt 0) {
    $OldFiles = Get-ChildItem -Path $LocationLogDir -File | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays) }
    if ($OldFiles) {
        $OldFiles | Remove-Item -Force
        Write-MirrorLog "Removed $($OldFiles.Count) old log files" "INFO"
    }
}

Write-MirrorLog "Mirror operation finished for $LocationServer" "INFO"
exit $OverallExitCode
