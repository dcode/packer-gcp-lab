# TODO: Seems deprecated. Checkout https://msendpointmgr.com/2016/08/03/customize-pinned-items-on-taskbar-in-windows-10-1607-during-osd-with-configmgr/
copy "A:\WindowsPowerShell.lnk" "${Env:Temp}\Windows PowerShell.lnk"
A:\PinTo10.exe /PTFOL01:'${Env:Temp}' /PTFILE01:'Windows PowerShell.lnk'

