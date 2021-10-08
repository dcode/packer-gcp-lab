function Optimize-Image {
  <#
      .SYNOPSIS
        Runs storage optimizations operations on the system volume.
      .DESCRIPTION
        Runs Defrag and Retrim commands on the system volume.
        This can reduce disk usage and increase HDD performance.
    #>
  
  $pn = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ProductName).ProductName
  # No trim support in Windows versions prior to Windows 2012.
  # As defrag can possibly enlarge the image without trim,
  # skipping this scenario.
  if ($pn -like 'Windows Server 2008*' -or $pn -like 'Windows 7*') {
    return
  }
  
  Write-Host "Defragging $($env:SystemDrive)"
  
  # Defrags C:
  # This should increase performance on HDD disks.
  Optimize-Volume -Verbose -Defrag -DriveLetter $env:SystemDrive[0]
  
  Write-Host "Retrimming $($env:SystemDrive)"
  
  # Retrims C:
  # This can reduce disk usage of PD disks, and subsequently of images.
  Optimize-Volume -Verbose -ReTrim -DriveLetter $env:SystemDrive[0]
}
  
Optimize-Image