# Downloads and extracts the SteamCMD client
$steamPath = 'C:\SteamCMD\'
Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile "$env:TEMP\SteamCMD.zip"
Expand-Archive -LiteralPath "$env:TEMP\SteamCMD.zip" -DestinationPath "C:\SteamCMD"
$processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
$processStartInfo.FileName = Join-Path $steamPath 'SteamCMD.exe'
$processStartInfo.UseShellExecute = $true
$processStartInfo.Verb = "RunAs"
$processStartInfo.Arguments = "/S"
$process = [System.Diagnostics.Process]::Start($processStartInfo)
$process.WaitForExit(60000)

# Installs/Updates the server
$updatePath = Join-Path $steamPath 'update.bat'
Set-Location $steamPath
New-Item -Path $updatePath -ItemType File
Set-Content -Path $updatePath -Value "steamcmd.exe +login anonymous +app_update 896660 +quit"
Start-Process -FilePath $updatePath -verb RunAs -Wait

# Configures the server
$startServerPath = Join-Path $steamPath 'steamapps\common\Valheim dedicated server\start_headless_server.bat'
$content = '@echo off
set SteamAppId=892970
echo "Starting server PRESS CTRL-C to exit"
valheim_server.exe -nographics -batchmode -name "TestName" -port 2456 -world "TestFilename" -password "TestPassword" -public 1'
Set-Content -Path $startServerPath -Value $content

# Creates the Windows Firewall rules
$serverExePath = Join-Path $steamPath "steamapps\common\Valheim dedicated server\valheim_server.exe"
$ruleName = "AllowValheimApp"
$ruleDescription = "Allow the Valheim dedicated server application"

New-NetFirewallRule -DisplayName $ruleName -Description $ruleDescription `
                    -Direction Inbound `
                    -Action Allow `
                    -Program $serverExePath 

New-NetFirewallRule -DisplayName 'AllowValheimTCP' `
                    -Profile 'Public' `
                    -Direction Inbound `
                    -Action Allow `
                    -Protocol TCP `
                    -LocalPort 2456-2458                    

New-NetFirewallRule -DisplayName 'AllowValheimUDP' `
                    -Profile 'Public' `
                    -Direction Inbound `
                    -Action Allow `
                    -Protocol UDP `
                    -LocalPort 2456-2458 
