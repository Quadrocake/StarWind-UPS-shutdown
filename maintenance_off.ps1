Import-Module Posh-SSH
Import-Module StarWindX

$isLinux = $true ## $true for StarWind VSAN for vSphere and $false for StarWind VSAN for Hyper-V

$WinServiceName = 'StarWindService'
$LinServiceName = 'StarWindVSA.service'

$StarWind = '192.168.12.214' #specify your StarWind VM (or host) ip-address
$Password = Get-Content C:\shutdown\cred4vm.txt | ConvertTo-SecureString
$Cred = New-Object System.Management.Automation.PSCredential ('root', $password)

function Exit-SWMaintenanceMode {
    try{
        $server = New-SWServer -host $StarWind -port 3261 -user root -password starwind
        $server.Connect()
        write-host "Devices:" -foreground yellow
        foreach($device in $server.Devices){
            if(!$device){
                Write-Host "No device found" -foreground red
                return
            } else {
                $device.Name
                $disk = $device.Name
                if ($device.Name -like "HAimage*"){
                    $device.SwitchMaintenanceMode($false, $true)
                    write-host "$disk exited maintenance mode"
                } else {
                    write-host "$disk is not an HA device, maintenance mode is not supported"
                }
            }
        }
    } catch {
        Write-Host $_ -foreground red
    } finally {
        $server.Disconnect()
    }
}

Write-Host "Confirming the StarWind VSAN service is running"
if($isLinux -eq $true){
    $SSHSession = New-SSHSession -ComputerName $starwind -Credential $cred -AcceptKey:$true
    $SSH = $SSHSession | New-SSHShellStream
    $SSH.WriteLine("systemctl status $LinServiceName")
    Start-Sleep -Seconds 2
    $systemctlstate = $SSH.read()
    if ($systemctlstate -notlike "*active (running)*"){
        $SSH.WriteLine("systemctl start $LinServiceName")
        Write-host "$LinServiceName has been started"
    } else {
        write-host "$LinServiceName is running"
    }
    $SSHSession | Remove-SSHSession | out-null
} else {
    $arrService = Get-Service -Name $WinServiceName
    if ($arrService.Status -ne "Running"){ 
        Start-Service $WinServiceName
        Write-Host "$WinServiceName is running"
    }
}
Start-Sleep -Seconds 10
Exit-SWMaintenanceMode
#Unregister-ScheduledTask -TaskName "Maintenance Mode off" -Confirm:$false