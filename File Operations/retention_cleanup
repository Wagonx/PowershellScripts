#############################################################
# Log Retention Script - Removes files older than 3 years
# Usage: powershell.exe -File FileCleanup.ps1 -FolderPath "C:\Path\To\Your\Folder"
# Log file for script is generated in "%appdata%\Local\Temp\FileCleanupLogs"
#############################################################

param(
    [Parameter(Mandatory=$true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$LogResults = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:USERPROFILE\appdata\Local\Temp\FileCleanupLogs"
)

# Create log directory if it doesn't exist
if ($LogResults -and -not (Test-Path -Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Create log file with timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "$LogPath\FileCleanup_$timestamp.log"

function Write-Log {
    param([string]$message)
    
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message"
    
    if ($LogResults) {
        Add-Content -Path $logFile -Value $logEntry
    }
    
    Write-Output $logEntry
}

# Validate that the folder exists
if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    Write-Log "ERROR: The specified folder does not exist: $FolderPath"
    exit 1
}

# Calculate the date 3 years ago
$cutoffDate = (Get-Date).AddYears(-3)

Write-Log "Starting cleanup of files older than $cutoffDate in folder: $FolderPath"
Write-Log "WhatIf mode: $WhatIf"

try {
    # Get all files (not directories) older than the cutoff date
    $oldFiles = Get-ChildItem -Path $FolderPath -File -Recurse | 
                Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    $totalFiles = $oldFiles.Count
    $totalSize = ($oldFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    
    Write-Log "Found $totalFiles files older than 3 years (approximately $($totalSize.ToString('0.00')) MB)"
    
    if ($totalFiles -eq 0) {
        Write-Log "No files to clean up."
        exit 0
    }
    
    $deletedCount = 0
    $errorCount = 0
    
    foreach ($file in $oldFiles) {
        try {
            if ($WhatIf) {
                Write-Log "WOULD DELETE: $($file.FullName) (Last modified: $($file.LastWriteTime))"
            }
            else {
                Remove-Item -Path $file.FullName -Force
                Write-Log "DELETED: $($file.FullName) (Last modified: $($file.LastWriteTime))"
                $deletedCount++
            }
        }
        catch {
            Write-Log "ERROR deleting file: $($file.FullName). $($_.Exception.Message)"
            $errorCount++
        }
    }
    
    if ($WhatIf) {
        Write-Log "SUMMARY: Would have deleted $totalFiles files (approximately $($totalSize.ToString('0.00')) MB)"
    }
    else {
        Write-Log "SUMMARY: Successfully deleted $deletedCount of $totalFiles files with $errorCount errors"
    }
}
catch {
    Write-Log "ERROR: An unexpected error occurred: $($_.Exception.Message)"
    exit 1
}

Write-Log "Cleanup operation completed"
