param(
    [Parameter(Mandatory=$true)]
    [string]$ComPort
)

# Add Windows API function signatures
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Win32API
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(
        IntPtr hDevice,
        uint dwIoControlCode,
        IntPtr lpInBuffer,
        uint nInBufferSize,
        IntPtr lpOutBuffer,
        uint nOutBufferSize,
        out uint lpBytesReturned,
        IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint OPEN_EXISTING = 3;
    public const uint FILE_ATTRIBUTE_NORMAL = 0x80;
    public static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);
    
    // PL-2303 specific IOCTL code from the disassembly
    public const uint PL2303_IOCTL_GET_VERSION = 0x222068;
}
"@

function Get-PL2303ChipVersion {
    param([string]$PortName)
    
    # Ensure COM port format
    if ($PortName -notmatch "^COM\d+$") {
        if ($PortName -match "^\d+$") {
            $PortName = "COM$PortName"
        } else {
            throw "Invalid COM port format. Use COMx or just the number."
        }
    }
    
    # Convert to device path format
    $devicePath = "\\.\$PortName"
    
    Write-Verbose "Attempting to detect PL-2303 chip on $PortName..."
    
    # Open handle to COM port
    $handle = [Win32API]::CreateFile(
        $devicePath,
        [Win32API]::GENERIC_READ -bor [Win32API]::GENERIC_WRITE,
        0,  # No sharing
        [IntPtr]::Zero,
        [Win32API]::OPEN_EXISTING,
        [Win32API]::FILE_ATTRIBUTE_NORMAL,
        [IntPtr]::Zero
    )
    
    if ($handle -eq [Win32API]::INVALID_HANDLE_VALUE) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to open $PortName. Error code: $errorCode. Make sure the port exists and isn't in use."
    }
    
    try {
        # Allocate buffer for the response (1 byte should be enough based on the disassembly)
        $outputBuffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)
        $bytesReturned = 0
        
        try {
            # Send the PL-2303 version query IOCTL
            $success = [Win32API]::DeviceIoControl(
                $handle,
                [Win32API]::PL2303_IOCTL_GET_VERSION,
                [IntPtr]::Zero,  # No input buffer
                0,               # No input
                $outputBuffer,   # Output buffer
                4,               # Output buffer size
                [ref]$bytesReturned,
                [IntPtr]::Zero
            )
            
            if (-not $success) {
                $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Warning "DeviceIoControl failed with error code: $errorCode. This may not be a PL-2303 device, or the device doesn't support this query."
                return $null
            }
            
            if ($bytesReturned -eq 0) {
                Write-Warning "No data returned from device."
                return $null
            }
            
            # Read the version byte from the response
            $versionByte = [System.Runtime.InteropServices.Marshal]::ReadByte($outputBuffer)
            
            Write-Verbose "Raw version byte: 0x$($versionByte.ToString('X2'))"
            
            # Map version byte to chip type (from the disassembly)
            $chipType = switch ($versionByte) {
                0x01 { "PL-2303 H chip" }
                0x02 { "PL-2303 XA / HXA chip" }
                0x04 { "PL-2303 HXD chip" }
                0x05 { "PL-2303 TA chip" }
                0x06 { "PL-2303 TB chip" }
                0x07 { "PL-2303 SA chip" }
                0x08 { "PL-2303 EA chip" }
                0x09 { "PL-2303 RA chip" }
                default { "Unknown PL-2303 variant or not a PL-2303 chip" }
            }
            
            return [PSCustomObject]@{
                Port = $PortName
                VersionByte = $versionByte
                VersionByteHex = "0x$($versionByte.ToString('X2'))"
                ChipType = $chipType
                IsValidPL2303 = $versionByte -in @(0x01, 0x02, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09)
            }
            
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($outputBuffer)
        }
        
    } finally {
        [Win32API]::CloseHandle($handle) | Out-Null
    }
}

# Main execution
try {
    $result = Get-PL2303ChipVersion -PortName $ComPort
    
    if ($result) {
        Write-Output $result
    } else {
        Write-Error "Could not detect PL-2303 chip on $ComPort. This could mean the device is not a PL-2303 chip, doesn't respond to this IOCTL, or the port is in use."
    }
    
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
