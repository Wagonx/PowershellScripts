# Simple PowerShell Script to Add Windows Printer

param(
    [Parameter(Mandatory=$true)]
    [string]$PrinterName,
    
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,
    
    [Parameter(Mandatory=$true)]
    [string]$DriverName,
    
    [Parameter(Mandatory=$true)]
    [string]$DriverPath,
    
    [string]$PortName = "IP_$IPAddress"
)

try {
    # Install driver from folder
    pnputil /add-driver "$DriverPath\*.inf" /install

    # Remove existing printer if it exists
    Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue | Remove-Printer -Confirm:$false

    # Remove existing port if it exists
    Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue | Remove-PrinterPort -Confirm:$false

    # Create printer port
    Add-PrinterPort -Name $PortName -PrinterHostAddress $IPAddress

    # Add printer
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName

} catch {
    Write-Error "Failed to install printer: $($_.Exception.Message)"
    exit 1
}
