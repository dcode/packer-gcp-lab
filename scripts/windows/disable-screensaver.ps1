Write-Host "Disabling Screensaver"
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name ScreenSaveActive -Value 0 -Type DWord
& powercfg -x -monitor-timeout-ac 0
& powercfg -x -monitor-timeout-dc 0


function Set-Power {
    <#
      .SYNOPSIS
        Change power settings to never turn off monitor.
    #>
  
    Write-Host 'Modify power settings to disable monitor power down.'
    Get-CimInstance -Namespace 'root\cimv2\power' -ClassName Win32_PowerSettingDataIndex -ErrorAction SilentlyContinue | ForEach-Object {
        $power_setting = $_ | Get-CimAssociatedInstance -ResultClassName 'Win32_PowerSetting' -OperationTimeoutSec 10 -ErrorAction SilentlyContinue
        # Change power configuration to never turn off monitor.  If Windows turns
        # off its monitor, it will respond to power button pushes by turning it back
        # on instead of shutting down as GCE expects.  We fix this by switching the
        # "Turn off display after" setting to 0 for all power configurations.
        if ($power_setting -and $power_setting.ElementName -eq 'Turn off display after') {
            Write-Host ('Changing power setting ' + $_.InstanceID)
            $_ | Set-CimInstance -Property @{SettingIndexValue = 0 }
        }
        # Set the "Sleep button action" setting to 1 for all power configurations
        # so the instance responds to standby requests.
        if ($power_setting -and $power_setting.ElementName -eq 'Sleep button action') {
            Write-Host ('Changing power setting ' + $_.InstanceID)
            $_ | Set-CimInstance -Property @{SettingIndexValue = 1 }
        }
    }
}

Set-Power