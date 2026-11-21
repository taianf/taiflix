<#
.SYNOPSIS
    Configures WSL2 mirrored mode and opens Windows Firewall permanently.
.DESCRIPTION
    1. Creates/Updates %USERPROFILE%\.wslconfig with networkingMode=mirrored and hostAddressLoopback=true under [experimental].
    2. Opens Windows Firewall ports for Jellyfin (8096) and Seerr (5055).
    3. Cleans up old netsh portproxy rules.
    4. Restarts WSL to apply mirrored networking.
#>

# Requires Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator in PowerShell!" -ForegroundColor Red
    Write-Host "Right-click PowerShell -> 'Run as Administrator', then run:" -ForegroundColor Yellow
    Write-Host "cd '$PSScriptRoot'; .\enable-mirrored-mode.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Setting up WSL2 Mirrored Networking (Permanent) ===" -ForegroundColor Cyan

# 1. Configure .wslconfig
$wslConfigFile = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfigContent = @"
[wsl2]
networkingMode=mirrored

[experimental]
hostAddressLoopback=true
autoProxy=true
"@

Write-Host "`n[1/3] Writing $wslConfigFile..." -ForegroundColor Cyan
Set-Content -Path $wslConfigFile -Value $wslConfigContent -Encoding UTF8
Write-Host "✓ .wslconfig saved successfully." -ForegroundColor Green

# 2. Configure Windows Firewall & clean portproxy
Write-Host "`n[2/3] Configuring Windows Firewall..." -ForegroundColor Cyan

# Clean old rules
netsh advfirewall firewall delete rule name="Jellyfin (Taiflix)" 2>$null | Out-Null
netsh advfirewall firewall delete rule name="Jellyfin TV" 2>$null | Out-Null
netsh advfirewall firewall delete rule name="Seerr (Taiflix)" 2>$null | Out-Null
netsh advfirewall firewall delete rule name="Seerr TV" 2>$null | Out-Null

# Clean obsolete portproxy mappings
netsh interface portproxy delete v4tov4 listenport=8096 listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy delete v4tov4 listenport=5055 listenaddress=0.0.0.0 2>$null | Out-Null

# Add permanent inbound firewall rules
netsh advfirewall firewall add rule name="Jellyfin (Taiflix)" dir=in action=allow protocol=TCP localport=8096 profile=any | Out-Null
netsh advfirewall firewall add rule name="Seerr (Taiflix)" dir=in action=allow protocol=TCP localport=5055 profile=any | Out-Null
Write-Host "✓ Windows Firewall rules added permanently (Ports 8096, 5055)." -ForegroundColor Green

# 3. Restart WSL
Write-Host "`n[3/3] Restarting WSL..." -ForegroundColor Cyan
wsl --shutdown
Write-Host "✓ WSL has been shut down to reload networking." -ForegroundColor Green

# Done
$localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet' -and $_.IPAddress -like "192.168.*" }).IPAddress | Select-Object -First 1

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  Setup Complete! Mirrored mode is now permanent." -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Now start your NixOS WSL terminal again, and access:"
if ($localIp) {
    Write-Host "  Jellyfin: http://${localIp}:8096" -ForegroundColor Yellow
    Write-Host "  Seerr:    http://${localIp}:5055" -ForegroundColor Yellow
} else {
    Write-Host "  Jellyfin: http://<YOUR_PC_IP>:8096" -ForegroundColor Yellow
}
Write-Host "`nThis will persist across computer restarts." -ForegroundColor Green
