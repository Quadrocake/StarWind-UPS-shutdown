# Some variables
$vcenter = "192.168.1.235"
$username = "administrator@vsphere.local"
$username4host = "root"
$cluster = "SW-SUP-CLUSTER"
$datacenter = "SWDATACENTER"
$vCenterVMName = "SW-SUP-VCENTER" #Name of vCenter VM
$StarWindVM1 = "SW-SUP-FS-00" #Name of first StarWind VM
$StarWindVM2 = "SW-SUP-FS-01" #Name of second StarWind VM
$ESXIhost1 = "192.168.1.231" #Name of first ESXI Host
$ESXIhost2 = "192.168.1.232" #Name of second ESXI Host
$StarWindIP = "192.168.10.10" #IP of StarWind VM

$password = get-content C:\shutdown\cred.txt | convertto-securestring
$password4host = get-content C:\shutdown\cred4host.txt | convertto-securestring
$credentials = new-object System.Management.Automation.PSCredential $username, $password
$credentials4host = new-object System.Management.Automation.PSCredential $username4host, $password4host
$time = ( get-date ).ToString('HH-mm-ss')
$date = ( get-date ).ToString('dd-MM-yyyy')
$filename = "c:\shutdown\poweredonvms-$date-$time.csv"
$logfile = New-Item -type file "C:\shutdown\ShutdownLog-$date-$time.txt" -Force

Write-Host ""
Write-Host "Shutdown command has been sent to the vCenter Server." -Foregroundcolor yellow
Write-Host "This script will shutdown all of the VMs and hosts located in $datacenter." -Foregroundcolor yellow
Write-Host ""
Sleep 5
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) PowerOff Script Engaged"
Add-Content $logfile ""

# Connect to vCenter
$counter = 0
if ($counter -eq 0){
       Set-PowerCLIConfiguration -InvalidCertificateAction ignore -Confirm:$false | Out-Null
}
Write-Host "Connecting to vCenter - $vcenter.... " -nonewline
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -confirm:$false
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Connecting to vCenter - $vcenter"
$success = Connect-VIServer $vcenter -Credential $credentials -WarningAction:SilentlyContinue
if ($success) { Write-Host "Connected!" -Foregroundcolor Green }
else
{
    Write-Host "Something is wrong, Aborting script" -Foregroundcolor Red
    Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Something is wrong, Aborting script"
    exit
}
Write-Host ""
Add-Content $logfile  ""

# Turn Off vApps
Write-Host "Stopping VApps...." -Foregroundcolor Green
Write-Host ""
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Stopping VApps..."
Add-Content $logfile ""
$vapps = Get-VApp | Where { $_.Status -eq "Started" }
if ($vapps -ne $null)
{
    ForEach ($vapp in $vapps)
    {
            Write-Host "Processing $vapp.... " -ForegroundColor Green
            Write-Host ""
            Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Stopping $vapp."
            Add-Content $logfile ""
            Stop-VApp -VApp $vapp -Confirm:$false | out-null
            Write-Host "$vapp stopped." -Foregroundcolor Green
            Write-Host ""
    }
}
Write-Host "VApps stopped." -Foregroundcolor Green
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) VApps stopped."
Add-Content $logfile ""

# Change DRS Automation level to partially automated...
Write-Host "Changing cluster DRS Automation Level to Partially Automated" -Foregroundcolor green
Get-Cluster $cluster | Set-Cluster -DrsAutomation PartiallyAutomated -confirm:$false

# Change the HA Level
Write-Host ""
Write-Host "Disabling HA on the cluster..." -Foregroundcolor green
Write-Host ""
Add-Content $logfile "Disabling HA on the cluster..."
Add-Content $logfile ""
Get-Cluster $cluster | Set-Cluster -HAEnabled:$false -confirm:$false

# Get VMs again (we will do this again instead of parsing the file in case a VM was powered in the nanosecond that it took to get here....
Write-Host ""
Write-Host "Retrieving a list of powered on guests...." -Foregroundcolor Green
Write-Host ""
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Retrieving a list of powered on guests...."
Add-Content $logfile ""
$poweredonguests = Get-VM -Location $cluster | where-object {$_.PowerState -eq "PoweredOn" }
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Checking to see if vCenter is virtualized"

# Retrieve host info for vCenter
if ($vcenterVMName -ne "NA")
{
    Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) vCenter is indeed virtualized, getting ESXi host hosting vCenter Server"
    $vCenterHost = (Get-VM $vCenterVMName).Host.Name
    Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $vCenterVMName currently running on $vCenterHost - will process this last"
}
else
{
    Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) vCenter is not virtualized"
}
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Proceeding with VM PowerOff"
Add-Content $logfile ""
# And now, let's start powering off some guests....

ForEach ( $guest in $poweredonguests )
{
    if ($guest.Name -notmatch $vCenterVMName -and $guest.Name -notmatch $StarWindVM1 -and $guest.Name -notmatch $StarWindVM2)
    {
        Write-Host "Processing $guest.... " -ForegroundColor Green
        Write-Host "Checking for VMware tools install" -Foregroundcolor Green
        $guestinfo = get-view -Id $guest.ID
        if ($guestinfo.config.Tools.ToolsVersion -eq 0)
        {
            Write-Host "No VMware tools detected in $guest , hard power this one" -ForegroundColor Yellow
            Write-Host ""
            Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $guest - no VMware tools, hard power off"
            Stop-VM $guest -confirm:$false | out-null
        }
        else
        {
           write-host "VMware tools detected.  I will attempt to gracefully shutdown $guest"
           Write-Host ""
           Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $guest - VMware tools installed, gracefull shutdown"
           $vmshutdown = $guest | shutdown-VMGuest -Confirm:$false | out-null
        }
    }
}

# Let's wait a minute or so for shutdowns to complete
Write-Host ""
Write-Host "Giving VMs 2 minutes before resulting in hard power off"
Write-Host ""
Add-Content $logfile ""
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Waiting a couple minutes then hard powering off all remaining VMs"
Sleep 120

# Now, let's go back through again to see if anything is still powered on and shut it down if it is
Write-Host "Beginning Phase 2 - anything left on.... night night...." -ForegroundColor red
Write-Host ""

# Get our list of guests still powered on...
$poweredonguests = Get-VM -Location $cluster | where-object {$_.PowerState -eq "PoweredOn" }
if ($poweredonguests -ne $null)
{
    ForEach ( $guest in $poweredonguests )
    {
        if ($guest.Name -notmatch $vCenterVMName -and $guest.Name -notmatch $StarWindVM1 -and $guest.Name -notmatch $StarWindVM2)
        {
            Write-Host "Processing $guest ...." -ForegroundColor Green
            #no checking for toosl, we just need to blast it down...
            write-host "Shutting down $guest - I don't care, it just needs to be off..." -ForegroundColor Yellow
                        Write-Host ""
            Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $guest - Hard Power Off"
            Stop-VM $guest -confirm:$false | out-null
        }
    }
}

# Wait 30 seconds
Write-Host "Waiting 30 seconds and then proceeding with host power off"
Write-Host ""
Sleep 30
Write-Host "Putting StarWind devices in to Maintenance Mode "
Write-Host ""

#Getting StarWind devices in to "Maintenance Mode"
Import-Module StarWindX
try
{
    $server = New-SWServer -host $StarWindIP -port 3261 -user root -password starwind
    $server.Connect()
    write-host "Devices:" -foreground yellow
    foreach($device in $server.Devices){
        if( !$device ){
            Write-Host "No device found" -foreground red
            return
        } else {
            $device.Name
            $disk = $device.Name
            if ($device.Name -like "HAimage*"){
                $device.SwitchMaintenanceMode($true, $true)
                write-host "$disk entered maintenance mode"
            } else {
                write-host "$disk is not an HA device, maintenance mode is not supported"
            }
        }
    }
}
catch
{
       Write-Host $_ -foreground red
}
finally
{
       $server.Disconnect()
}

Add-Content $logfile ""
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Processing power off of all hosts now"
Sleep 30

# and now its time to slam down the hosts - I've chosen to go by datacenter here but you could put the cluster
# There are some standalone hosts in the datacenter that I would also like to shutdown, those vms are set to
# start and stop with the host, so i can just shut those hosts down and they will take care of the vm shutdown
shutdown-VMGuest $vCenterVMName -Confirm:$false
Write-Host "Waiting for vCenter shutdown" -ForegroundColor Green
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Shutting down $vCenterVMName"
Sleep 300
Connect-VIServer $ESXIhost1 -Credential $credentials4host -WarningAction:SilentlyContinue
        Write-Host "Shutting down $ESXIhost1" -ForegroundColor Green
        Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Shutting down $ESXIhost1"
        Stop-VMHost $ESXIhost1 -Confirm:$false -Force
Sleep 120
Connect-VIServer $ESXIhost2 -Credential $credentials4host -WarningAction:SilentlyContinue
        Write-Host "Shutting down $ESXIhost2" -ForegroundColor Green
        Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Shutting down $ESXIhost2"
        Stop-VMHost $ESXIhost2 -Confirm:$false -Force
Add-Content $logfile ""
Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) All done!"
# That's a wrap