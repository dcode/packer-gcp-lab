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
    if ($PSCmdlet.ShouldProcess($Executable)) {
        $out = Start-Process "${Executable}" -Wait -NoNewWindow -ArgumentList "${Arguments}" 2>&1 | Out-String
        $out.Trim()    
    }
}

function Install-Driver {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Path
    )

    # Get the OS-specific dir
    $os_path = Get-ChildItem "${Path}" -Filter (Get-WindowsVersion)

    # Get the arch-specific dir
    $os_arch_path = Get-ChildItem "${os_path}" -Filter "${Env:PROCESSOR_ARCHITECTURE}"

    # Find .inf file
    $inf_file = Get-ChildItem "${os_arch_path}" -Filter '*.inf'

    if ($PSCmdlet.ShouldProcess($inf_file.Name)) {
        Invoke-Command pnputil /add-driver $inf_file.FullName
    }
}

function Get-WindowsVersion {
    $OS = $null

    switch ((Get-CimInstance Win32_OperatingSystem).BuildNumber) { 
        9200 { $OS = "2k12" }
        9600 { $OS = "2k12R2" }
        14393 { $OS = "2k16" }
        16229 { $OS = "2k16" }
        { $_ -ge 10240 -and $_ -lt 22000 } { $OS = "w10" }
        default { $OS = "Not Listed" }
    }

    return $OS
}

function Install-MSI {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Specifies the file object for the MSI file.")]
        [System.IO.FileInfo] $File
    ) 
    $dtstamp = Get-date -Format "yyyyMMddTHHmmss"
    $logFile = '{0}-{1}.log' -f $file.FullName, $dtstamp

    if ($PSCmdlet.ShouldProcess($file.Name)) {
        Invoke-Command "msiexec.exe" /i ("{0}" -f $file.FullName) /qn /norestart /L*v "${logfile}"
    }
}

function Install-GuestAgent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Specifies the path to the virtio-win driver disk or folder.")]
        [string]$DriverDisk
    ) 

    # Ensure we have the serial driver installed
    $vioserial_drv = Get-ChildItem "${DriverDisk}" -Filter 'vioserial'
    Install-Driver "${vioserial_drv}"

    $os_arch = $null
    $addr_size = (Get-WmiObject Win32_Processor).AddressWidth
    switch ($addr_size) { 
        32 { $os_arch = "i386" }
        64 { $os_arch = "x86_64" }
    }

    if ($os_arch = = $null) {
        Throw "Unsupported architecture for Qemu Agent: {0}" -f "${addr_size}"
    }

    # Install the agent
    $installer = Get-ChildItem "${DriverDisk}/guest-agent" -Filter "*${os_arch}.msi"
    Install-MSI -File ${installer}
    

}

Install-GuestAgent -DriverDisk "D:\"