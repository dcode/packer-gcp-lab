## This script was adapted from several different packer builds and Google's daisy workflow and a lot of trial and error

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'
$script:hosts_file = "$env:windir\system32\drivers\etc\hosts"

function ThrowOnNativeFailure {
    if (-not $?) {
        throw 'Native Failure'
    }
}

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

function Install-Drivers {

    Write-Host 'Installing GCE packages...'

    $env:GooGetRoot = "$env:ProgramData\GooGet"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://github.com/google/googet/releases/download/v2.18.3/googet.exe"
    (New-Object System.Net.WebClient).DownloadFile($url, "$env:temp\googet.exe")

    & "$env:temp\googet.exe" -noconfirm install -sources `
        https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable googet;

    # Cleanup
    Remove-Item "$env:temp\googet.exe"

    # Temporarily add this to the path
    $env:PATH += ";$env:GooGetRoot"

    googet addrepo google-compute-engine-stable https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable

    # Install core Windows guest environment
    # Install each individually in order to catch individual errors
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-windows
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-powershell
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-metadata-scripts 
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-sysprep
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install certgen
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-driver-gvnic
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-diagnostics
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-osconfig-agent
 
    # Google Graphics Array not supported on 2008R2/7 (6.1)
    if ($pn -notlike 'Windows Server 2008*' -or $pn -notlike 'Windows 7*') {
        Write-Host 'Installing GCE virtual display driver...'
        Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-driver-gga
    }

    if ($pn -match 'Windows (Web )?Server (2008 R2|2012 R2|2016|2019|Standard|Datacenter)') {
        Write-Host 'Installing GCE VSS agent and provider...'
        Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-vss
    }

    Write-Host "List installed packages before drivers"
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' installed

    # Remove existing drivers that are not from Google
    $conflicting_drivers = Get-WindowsDriver -Online |
    Where-Object {
        (
            $_.OriginalFileName -like "*gga*" -or
            $_.OriginalFileName -like "*vioscsi*" -or
            #$_.OriginalFileName -like "*netkvm*" -or
            $_.OriginalFileName -like "*pvpanic*" -or
            $_.OriginalFileName -like "*balloon*"
        ) -and (
            $_.ProviderName -notlike "*Google*"
        )
    }

    Write-Host "Found conflicting drivers: "
    Write-Host $conflicting_drivers

    foreach ($item in $conflicting_drivers) {
        # Remove the current driver, will require a reboot
        Write-Host ( "Deleting driver {0} by {1} (ver {2})." -f $item.Driver, $item.ProviderName, $item.Version )
        Invoke-Command pnputil /delete-driver $item.Driver /force
    }

    # Install virtual hardware drivers
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-driver-vioscsi
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-driver-pvpanic
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-driver-balloon
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-driver-netkvm -erroraction 'silentlycontinue'

    # Manually add the Google driver that failed
    $collection = "netkvm"

    foreach ($item in $collection) {
        # Manually replace driver
        $package_install_folder = Get-ChildItem -Path "$env:GooGetRoot\cache" -Filter "*driver-$item*" -Directory

        $script_dir = Join-Path $package_install_folder.Fullname "\script"
        Import-Module "$script_dir\package-common.psm1" -Force

        $driver_folder = Get-PackageContentsFolder "$item"
        $driver_folder = Join-Path $package_install_folder.Fullname "$driver_folder"
        if (!(Test-Path $driver_folder)) {
            throw "$driver_folder not found. Not a supported Windows version."
        }

        $conflicting_drivers = Get-WindowsDriver -Online |
        Where-Object {
            (
                $_.OriginalFileName -like "*$item*"
            ) -and (
                $_.ProviderName -notlike "*Google*"
            )
        }

        # Remove the current driver, will require a reboot
        foreach ($driver_inf in $conflicting_drivers) {
            Write-Host ("Deleting driver {0} named {1}" -f $item, $driver_inf.Driver)
            Invoke-Command pnputil /delete-driver $driver_inf.Driver /force
        }

        # Add google's driver
        Write-Output "Install driver from $driver_folder"
        $inf_file = Get-ChildItem $driver_folder -Filter '*.inf'
        Write-Host "Found $inf_file"
        Invoke-Command pnputil /add-driver $inf_file.FullName
    }

    # Register netkvmco.dll.
    # Invoke-Command rundll32 'netkvmco.dll,RegisterNetKVMNetShHelper'

    Write-Host "List installed packages"
    Invoke-Command 'C:\ProgramData\GooGet\googet.exe' installed
}



  
function Set-InstanceProperties {
    <#
      .SYNOPSIS
        Apply GCE specific changes.
      .DESCRIPTION
        Apply GCE specific changes to this instance.
    #>
  
    Write-Host 'Setting instance properties.'
  
    # Enable EMS.
    Invoke-Command bcdedit /bootems "{default}" ON
    Invoke-Command bcdedit /emssettings EMSPORT:2 EMSBAUDRATE:115200
    Invoke-Command bcdedit /ems "{default}" on
  
    # Ignore boot failures.
    Invoke-Command bcdedit /set '{current}' bootstatuspolicy ignoreallfailures
    Write-Host 'bcdedit option set.'
  
    # Registry fix for PD cluster size issue.
    $vioscsi_path = 'HKLM:\SYSTEM\CurrentControlSet\Services\vioscsi\Parameters\Device'
    if (-not (Test-Path $vioscsi_path)) {
        New-Item -Path $vioscsi_path
    }
    New-ItemProperty -Path $vioscsi_path -Name EnableQueryAccessAlignment -Value 1 -PropertyType DWord
  
    # Change SanPolicy. Setting is persistent even after sysprep. This helps in
    # ensuring all attached disks are online when instance is built.
    $san_policy = 'san policy=OnlineAll' | diskpart | Select-String 'San Policy'
    Write-Host ($san_policy -replace '(?<=>)\s+(?=<)') # Remove newline and tabs
  
    # Prevent password from expiring after 42 days.
    Invoke-Command net accounts /maxpwage:unlimited
  
    # Change time zone to Coordinated Universal Time.
    Invoke-Command tzutil /s 'UTC'
  
    # Set pagefile to 1GB
    Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPageFile = $False }
    Get-CimInstance Win32_PageFileSetting | Set-CimInstance -Property @{InitialSize = 1024; MaximumSize = 1024 }
  
    # Disable Administartor user.
    Invoke-Command net user Administrator /ACTIVE:NO
  
    # Set minimum password length.
    Invoke-Command net accounts /MINPWLEN:8
  
    # Enable access to Windows administrative file share.
    Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Force
  
    # https://support.microsoft.com/en-us/help/4072698/windows-server-guidance-to-protect-against-the-speculative-execution
    # Not enabling by default for now.
    #New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'FeatureSettingsOverride' -Value 0  -PropertyType DWORD -Force
    #New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'FeatureSettingsOverrideMask' -Value 3  -PropertyType DWORD -Force
}

  

function Initialize-Network {
    <#
      .SYNOPSIS
        Apply GCE networking related configuration changes.
    #>
  
    Write-Host 'Configuring network.'
  
    # Make sure metadata server is in etc/hosts file.
    Add-Content $script:hosts_file @'
# Google Compute Engine metadata server
    169.254.169.254    metadata.google.internal metadata
'@
  
    Write-Host 'Changing firewall settings.'
    # Change Windows Server firewall settings.
    # Enable ping in Windows Server 2008.
    Invoke-Command netsh advfirewall firewall add rule `
        name='ICMP Allow incoming V4 echo request' `
        protocol='icmpv4:8,any' dir=in action=allow
  
    # Enable inbound communication from the metadata server.
    Invoke-Command netsh advfirewall firewall add rule `
        name='Allow incoming from GCE metadata server' `
        protocol=ANY remoteip=169.254.169.254 dir=in action=allow
  
    # Enable outbound communication to the metadata server.
    Invoke-Command netsh advfirewall firewall add rule `
        name='Allow outgoing to GCE metadata server' `
        protocol=ANY remoteip=169.254.169.254 dir=out action=allow
  
    # Change KeepAliveTime to 5 minutes.
    $tcp_params = 'HKLM:\System\CurrentControlSet\Services\Tcpip\Parameters'
    New-ItemProperty -Path $tcp_params -Name 'KeepAliveTime' -Value 300000 -PropertyType DWord
  
    Write-Host 'Disabling WPAD.'
  
    # Mount default user registry hive at HKLM:\DefaultUser.
    Invoke-Command reg load 'HKLM\DefaultUser' 'C:\Users\Default\NTUSER.DAT'
  
    # Loop over default user and current (SYSTEM) user.
    foreach ($reg_base in 'HKLM\DefaultUser', 'HKCU') {
        # Disable Web Proxy Auto Discovery.
        $WPAD = "$reg_base\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  
        # Make change with reg add, because it will work with the mounted hive and
        # because it will recursively add any necessary subkeys.
        Invoke-Command reg add $WPAD /v AutoDetect /t REG_DWORD /d 0
    }
  
    # Unmount default user hive.
    Invoke-Command reg unload 'HKLM\DefaultUser'
}

function Initialize-NTP {
    <#
      .SYNOPSIS
        Setup NTP sync for GCE.
    #>
  
    Write-Host 'Configure NTP for GCP.'
  
    # Set the CMOS clock to use UTC.
    $tzi_path = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
    Set-ItemProperty -Path $tzi_path -Name RealTimeIsUniversal -Value 1
  
    # Set up time sync...
    # Stop in case it's running; it probably won't be.
    Stop-Service W32time
    # w32tm /unregister is flaky, but using sc delete first helps to clean up
    # the service reliably.
    Invoke-Command $env:windir\system32\sc.exe delete W32Time
  
    # Unregister and re-register the service.
    $w32tm = "$env:windir\System32\w32tm.exe"
    Invoke-Command $w32tm /unregister
    Invoke-Command $w32tm /register
  
    # Get time from GCE NTP server every 15 minutes.
    Invoke-Command $w32tm /config '/manualpeerlist:metadata.google.internal,0x1' /syncfromflags:manual
    # Start-Sleep -s 300
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' `
        -Name SpecialPollInterval -Value 900
    # Set in Control Panel -- Append to end of list, set default.
    $server_key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers'
    $server_item = Get-Item $server_key
    $server_num = ($server_item.GetValueNames() | Measure-Object -Maximum).Maximum + 1
    Set-ItemProperty -Path $server_key -Name $server_num -Value 'metadata.google.internal'
    Set-ItemProperty -Path $server_key -Name '(Default)' -Value $server_num
    # Configure to run automatically on every start.
    Set-Service W32Time -StartupType Automatic
    Invoke-Command $env:windir\system32\sc.exe triggerinfo w32time start/networkon
    Write-Host 'Configured W32Time to use GCE NTP server.'
  
    # Verify that the W32Time service is correctly installed. This has been
    # a source of flakiness in the past.
    try {
        Get-Service W32Time
    }
    catch {
        throw "Failed to configure NTP. Cannot complete image build: $($_.Exception.Message)"
    }
  
    # Sync time now.
    Start-Service W32time
    Invoke-Command $w32tm /resync
}

function Enable-WinRM {
    if ($pn -like '*Enterprise') {
        Write-Host 'Windows Client detected, enabling WinRM (including on Public networks).'
        & winrm quickconfig -quiet -force
    }
}

function Export-ImageMetadata {
    $computer_info = Get-ComputerInfo
    $version = $computer_info.OsVersion
    $family = 'windows-' + $computer_info.windowsversion
    $name = $computer_info.OSName
    $release_date = (Get-Date).ToUniversalTime()
    $image_metadata = @{'family' = $family;
        'version'                = $version;
        'name'                   = $name;
        'location'               = 'c:\';
        'build_date'             = $release_date;
        'packages'               = @()
    }

    # Get Googet packages.
    $out = & 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' 'installed'
    $out = $out -Split [Environment]::NewLine
    $out = $out[1..($out.length - 2)]
    [array]::sort($out)
  
    foreach ($package_line in $out) {
        $name = $package_line.Trim().Split(' ')[0]
        # Get Package Info for each package
        $info = Invoke-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' 'installed' '-info' $name
        $version = $info[2]
        $source = $info[6]
        $package_metadata = @{'name' = $name;
            'version'                = $version;
            'commmit_hash'           = $source
        }
        $image_metadata['packages'] += $package_metadata
    }
  
    # Save the JSON image_metadata.
    $image_metadata_json = $image_metadata | ConvertTo-Json -Compress
    $image_metadata_json | Out-File -FilePath "c:\metadata.json"
}
  

try {
    Write-Host 'Beginning GCE customizatin powershell script.'
    
    # Windows Product Name https://renenyffenegger.ch/notes/Windows/versions/index
    $pn = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ProductName).ProductName
  
    Set-InstanceProperties
    Initialize-Network
    Initialize-NTP
    Install-Drivers
    Enable-WinRM
    Export-ImageMetadata
  
    # Required for WMF 5.1 on Windows Server 2008R2
    # https://sccm-zone.com/fix-sysprep-error-on-windows-2008-r2-after-windows-management-framework-5-0-installation-b9e86b4c41e4
    if ($pn -like 'Windows Server 2008*') {
        # Only needed and applicable for 2008.
        & netsh interface ipv4 set dnsservers 'Local Area Connection' source=dhcp | Out-Null
    
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\StreamProvider' -Name LastFullPayloadTime -Value 0 -PropertyType DWord -Force
    }

    exit 0
}
catch {
    Write-Host 'Exception caught in script:'
    Write-Host $_.InvocationInfo.PositionMessage
    Write-Host "Message: $($_.Exception.Message)"
    Write-Host 'Windows build failed.'
    exit 1
}





































