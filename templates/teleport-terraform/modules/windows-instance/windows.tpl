<powershell>
Start-Transcript -Path "C:\UserData.log" -Append
$ErrorActionPreference = "Stop"

# Create Event Log source
New-EventLog -LogName "Application" -Source "TeleportSetup" -ErrorAction SilentlyContinue

try {
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1000 -EntryType Information -Message "Starting Teleport setup script"
    
    # --- Validate Variables ---
    $User = "${User}"
    $Password = "${Password}"
    $Domain = "${Domain}"
    $TeleportVersion = "${TeleportVersion}"
    $Env = "${Env}"
    
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1001 -EntryType Information -Message "Variables: User=$User, Domain=$Domain, Version=$TeleportVersion, Env=$Env"
    
    if ([string]::IsNullOrWhiteSpace($User) -or $User -like '*$*') {
        throw "User variable not properly substituted: $User"
    }
    
    Write-Host "Creating user: $User"
    
    # --- User Setup ---
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $User -Password $SecurePassword -FullName $User -PasswordNeverExpires
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $User
    Add-LocalGroupMember -Group "Administrators" -Member $User
    
    Write-Host "User created successfully"
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1002 -EntryType Information -Message "User $User created and added to RDP and Admin groups"
    
    # --- Test Network Connectivity ---
    Write-Host "Testing connectivity to Teleport domain: $Domain"
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1003 -EntryType Information -Message "Testing network connectivity to $Domain"
    
    $testConnection = Test-NetConnection -ComputerName $Domain -Port 443
    if (-not $testConnection.TcpTestSucceeded) {
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 9001 -EntryType Error -Message "Failed to connect to $Domain on port 443"
        throw "Cannot reach $Domain on port 443"
    }
    
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1004 -EntryType Information -Message "Network connectivity test passed for $Domain"
    
    # --- Teleport Certificate Download ---
    Write-Host "Downloading Teleport certificate"
    $certPath = "$env:TEMP\teleport.cer"
    $certUrl = "https://$Domain/webapi/auth/export?type=windows"
    
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1005 -EntryType Information -Message "Downloading certificate from $certUrl"
    Invoke-WebRequest -Uri $certUrl -OutFile $certPath -UseBasicParsing
    
    if (Test-Path $certPath) {
        $certSize = (Get-Item $certPath).Length
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1006 -EntryType Information -Message "Certificate downloaded successfully, size: $certSize bytes"
    } else {
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 9002 -EntryType Error -Message "Certificate file not found after download"
        throw "Certificate download failed"
    }
    
    # --- Teleport Installer Download and Install ---
    Write-Host "Downloading Teleport installer"
    $installerName = "teleport-windows-auth-setup-v$($TeleportVersion)-amd64.exe"
    $installerPath = "$env:TEMP\$installerName"
    $installerUrl = "https://cdn.teleport.dev/$installerName"
    
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1007 -EntryType Information -Message "Downloading installer from $installerUrl"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    
    if (Test-Path $installerPath) {
        $installerSize = (Get-Item $installerPath).Length
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1008 -EntryType Information -Message "Installer downloaded successfully, size: $installerSize bytes"
    } else {
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 9003 -EntryType Error -Message "Installer file not found after download"
        throw "Installer download failed"
    }
    
    Write-Host "Installing Teleport"
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1009 -EntryType Information -Message "Starting Teleport installation with cert=$certPath"
    
    $process = Start-Process -FilePath $installerPath -ArgumentList "install", "--cert=$certPath", "-r" -Wait -PassThru
    
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1010 -EntryType Information -Message "Teleport installer completed with exit code: $($process.ExitCode)"
    
    if ($process.ExitCode -ne 0) {
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 9004 -EntryType Error -Message "Teleport installation failed with exit code: $($process.ExitCode)"
        throw "Teleport installation failed with exit code: $($process.ExitCode)"
    }
    
    Write-Host "Teleport installed successfully"
    
    # Check if Teleport service exists and is running
    $teleportService = Get-Service -Name "Teleport*" -ErrorAction SilentlyContinue
    if ($teleportService) {
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1011 -EntryType Information -Message "Teleport service found: $($teleportService.Name), Status: $($teleportService.Status)"
    } else {
        Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 9005 -EntryType Warning -Message "No Teleport service found after installation"
    }
    
    # --- Rename Computer and Restart ---
    Write-Host "Renaming computer to: $Env-desktop"
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1012 -EntryType Information -Message "Renaming computer to $Env-desktop"
    
    Rename-Computer -NewName "$Env-desktop" -Force
    
    Write-Host "Setup complete. Restarting in 10 seconds..."
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 1013 -EntryType Information -Message "Setup completed successfully. Restarting in 10 seconds"
    
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
catch {
    Write-Error "Setup failed: $_"
    Write-Host "Error details: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    
    # Log to Event Log
    Write-EventLog -LogName "Application" -Source "TeleportSetup" -EventId 9999 -EntryType Error -Message "Setup failed: $($_.Exception.Message) `n`nStack trace: $($_.ScriptStackTrace)"
    
    # Don't restart on error so you can debug
    Stop-Transcript
    exit 1
}

Stop-Transcript
</powershell>

<persist>false</persist>