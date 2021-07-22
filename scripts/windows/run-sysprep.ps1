$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'

Write-Host 'Launching sysprep.'
& "$script:gce_install_dir\sysprep\gcesysprep.bat"