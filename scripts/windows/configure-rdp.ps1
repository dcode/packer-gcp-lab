function Invoke-Command {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Executable,
        [Parameter(ValueFromRemainingArguments = $true,
            ValueFromPipelineByPropertyName = $true)]
        $Arguments = $null
    )
    Write-Host "Running $Executable with arguments $Arguments."
    $out = &$executable $arguments 2>&1 | Out-String
    $out.Trim()
}
function Set-RDP {
    Write-Host 'Modifying RDP settings.'
    $ts_path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $registryPath = "${ts_path}\WinStations\RDP-Tcp"
  
    # Set minimum encryption level to "High"
    New-ItemProperty -Path $registryPath -Name MinEncryptionLevel -Value 3 -PropertyType DWORD -Force
    # Specifies that Network-Level user authentication is required.
    New-ItemProperty -Path $registryPath -Name UserAuthentication -Value 1 -PropertyType DWORD -Force
    # Specifies that the Transport Layer Security (TLS) protocol is used by the server and the client
    # for authentication before a remote desktop connection is established.
    New-ItemProperty -Path $registryPath -Name SecurityLayer -Value 2 -PropertyType DWORD -Force
  
    # Enable remote desktop in registry.
    Set-ItemProperty -Path $ts_path -Name 'fDenyTSConnections' -Value 0 -Force
  
    # Disable Ctrl + Alt + Del.
    Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableCAD' -Value 1 -Force
    Invoke-Command netsh advfirewall firewall set rule group='remote desktop' new enable=Yes
}

Set-RDP