Import-Module Posh-SSH
Import-Module StarWindX

$StarWindVM1 = '192.168.12.214' #IP of first StarWind VM
$StarWindVM2 = '192.168.12.239' #IP of second StarWind VM

$Password = Get-Content C:\shutdown\cred4vm.txt | ConvertTo-SecureString
$Cred = New-Object System.Management.Automation.PSCredential ('root', $password)

$time = ( get-date ).ToString('HH-mm-ss')
$date = ( get-date ).ToString('dd-MM-yyyy')
$logfile = New-Item -type file "C:\shutdown\StartUpLog-$date-$time.txt" -Force

# Function to exit maintenance mode for all StarWind devices
function Exit-SWMaintenanceMode {
    try {
        $server = New-SWServer -host $StarWindVM1 -port 3261 -user root -password starwind
        $server.Connect()
        write-host "Devices:" -foreground yellow
        foreach ($device in $server.Devices) {
            if (!$device) {
                Write-Host "No device found" -foreground red
				Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) No StarWind devices found"
                return
            } else {
                $device.Name
                $disk = $device.Name
                if ($device.Name -like "HAimage*") {
                    $device.SwitchMaintenanceMode($false, $false)
                    write-host "$disk exited maintenance mode"
					Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $disk - successfully turned off maintenance mode"
                } else {
                    write-host "$disk is not an HA device, maintenance mode is not supported"
					Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $disk - not an HA device, maintenance mode is not supported"
                }
            }
        }
    } catch {
        Write-Error $_ -foreground red -ErrorAction Stop
    } finally {
        $server.Disconnect()
    }
}

# Function to check StarWind service and start it if service is not active
function Check-SWServiceStatus($StarWindVM) {
    try {
		$SSHSession = New-SSHSession -ComputerName $StarWindVM -Credential $cred -AcceptKey:$true
		$SSH = $SSHSession | New-SSHShellStream
		$SSH.WriteLine("systemctl status $ServiceName")
		Start-Sleep -Seconds 2
		$systemctlstate = $SSH.read()
		if ($systemctlstate -notlike "*active (running)*") {
			$SSH.WriteLine("systemctl start StarWindVSA")
            
            Start-Sleep -Seconds 2
            $SSH.read()

            Write-host "$ServiceName on $StarWindVM has been started"
			Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $ServiceName on $StarWindVM has been started"
			
		} else {
			write-host "$ServiceName on $StarWindVM is already running"
			Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) $ServiceName on $StarWindVM is already running"
		}
	} catch {
		Write-Host $_ -foreground red
	} finally {
        $SSHSession | Remove-SSHSession | out-null
    }
}

# Function to start rescan script
function Start-RescanScript($StarWindVM) {
    try {
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

Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Checking if both ESXi hosts are available"

# Infinite cycle which is pinging both hosts until they will become available
while ($true) {
    if ((Test-Connection $StarWindVM1 -Quiet) -And (Test-Connection $StarWindVM2 -Quiet)) {
        
		Write-Host "Both hosts are online, trying to connect to StarWind service" -foreground green
		Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Both hosts are online"
		# When hosts are available it makes 5 attempts with 30 second intervals to exit maintenance mode
		For ($i=0; $i -lt 5; $i++) {
			try {
                Write-Host "Let's wait 30 seconds before trying to connect"
                Start-Sleep -Seconds 30
				Write-Host "Trying to exit maintenance mode"
				Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Exiting maintenance mode..."
				
				Exit-SWMaintenanceMode				

                Start-Sleep -Seconds 10
                Write-Host "Starting rescan script" 
				Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Starting rescan script on both hosts"
                
				Start-RescanScript($StarWindVM1)
                Start-RescanScript($StarWindVM2)

                Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) All done!"
				Break
			} catch {
				Write-Host "Let's check StarWInd service and start it if it's off"
				Add-Content $logfile "$(get-date -f dd/MM/yyyy) $(get-date -f HH:mm:ss) Failed to connect to StarWind service, trying to start it"
				
				Check-SWServiceStatus($StarWindVM1)
                Check-SWServiceStatus($StarWindVM2)
			}
		}
        Break
    } else {
        Write-Host "One or both hosts are not online" -foreground red
    }
}
