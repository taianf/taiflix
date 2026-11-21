# Run this script in PowerShell as Administrator to forward Jellyfin and Seerr ports to WSL2

$wslIp = "172.23.71.110"

Write-Host "Configuring port forwarding to WSL ($wslIp)..." -ForegroundColor Cyan

# Remove any old rules for these ports
netsh interface portproxy delete v4tov4 listenport=8096 listenaddress=0.0.0.0 2>$null
netsh interface portproxy delete v4tov4 listenport=5055 listenaddress=0.0.0.0 2>$null

# Add portproxy rules
netsh interface portproxy add v4tov4 listenport=8096 listenaddress=0.0.0.0 connectport=8096 connectaddress=$wslIp
netsh interface portproxy add v4tov4 listenport=5055 listenaddress=0.0.0.0 connectport=5055 connectaddress=$wslIp

# Firewall rules
netsh advfirewall firewall delete rule name="Jellyfin TV" 2>$null
netsh advfirewall firewall delete rule name="Seerr TV" 2>$null
netsh advfirewall firewall add rule name="Jellyfin TV" dir=in action=allow protocol=TCP localport=8096
netsh advfirewall firewall add rule name="Seerr TV" dir=in action=allow protocol=TCP localport=5055

Write-Host "`nActive Port Forwarding Rules:" -ForegroundColor Green
netsh interface portproxy show v4tov4

Write-Host "`nDone! Access on your TV at:" -ForegroundColor Yellow
Write-Host "Jellyfin: http://192.168.1.155:8096"
Write-Host "Seerr:    http://192.168.1.155:5055"
