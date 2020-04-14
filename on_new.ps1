Import-Module Posh-SSH
Import-Module StarWindX

$StarWindVM1 = '192.168.12.214'
$StarWindVM2 = '192.168.12.239'

$Password = Get-Content C:\shutdown\cred4vm.txt | ConvertTo-SecureString
$Cred = New-Object System.Management.Automation.PSCredential ('root', $password)

function Exit-SWMaintenanceMode {
    try{
        $server = New-SWServer -host $StarWindVM1 -port 3261 -user root -password starwind
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
                    $device.SwitchMaintenanceMode($false, $false)
                    write-host "$disk exited maintenance mode"
                } else {
                    write-host "$disk is not an HA device, maintenance mode is not supported"
                }
            }
        }
    } catch {
        Write-Error $_ -foreground red -ErrorAction Stop
    } finally {
        $server.Disconnect()
    }
}

function Check-SWServiceStatus($StarWindVM) {
    try{
		$SSHSession = New-SSHSession -ComputerName $StarWindVM -Credential $cred -AcceptKey:$true
		$SSH = $SSHSession | New-SSHShellStream
		$SSH.WriteLine("systemctl status $ServiceName")
		Start-Sleep -Seconds 2
		$systemctlstate = $SSH.read()
		if ($systemctlstate -notlike "*active (running)*"){
			$SSH.WriteLine("systemctl start StarWindVSA")
            
            Start-Sleep -Seconds 2
            $SSH.read()

            Write-host "$ServiceName has been started"
		} else {
			write-host "$ServiceName is running"
		}
	} catch {
		Write-Host $_ -foreground red
	} finally {
        $SSHSession | Remove-SSHSession | out-null
    }
}


function Start-RescanScript($StarWindVM) {

    try{
		$SSHSession = New-SSHSession -ComputerName $StarWindVM -Credential $cred -AcceptKey:$true
		$SSH = $SSHSession | New-SSHShellStream
		$SSH.WriteLine("/opt/StarWind/StarWindVSA/drive_c/StarWind/hba_rescan.ps1")
        Start-Sleep -Seconds 20
        $SSH.read()
	} catch {
		Write-Host $_ -foreground red
	} finally {
        $SSHSession | Remove-SSHSession | out-null
    }
}

while ($true) {
    if ((Test-Connection $StarWindVM1 -Quiet) -And (Test-Connection $StarWindVM2 -Quiet)) {
        Write-Host "Both hosts are online, trying to connect to StarWind service" -foreground green
		
		For ($i=0; $i -lt 5; $i++) {
			try{
                Write-Host "Let's wait 30 seconds before trying to connect"
                Start-Sleep -Seconds 30

				Write-Host "Trying to exit maintenance mode"
				Exit-SWMaintenanceMode

                Start-Sleep -Seconds 10

                Write-Host "Starting rescan script"
                Start-RescanScript($StarWindVM1)
                Start-RescanScript($StarWindVM2)

				Break
			} catch {
				Write-Host "Let's check StarWInd service and start it if it's off"
				Check-SWServiceStatus($StarWindVM1)
                Check-SWServiceStatus($StarWindVM2)
			}
		}
        Break
    }else {
        Write-Host "One or both hosts are not online" -foreground red
    }
}