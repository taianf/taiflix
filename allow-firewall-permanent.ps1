# Run this script ONCE in PowerShell as Administrator to open the Windows Firewall for Mirrored Mode.

Write-Host "Opening Windows Firewall for Jellyfin and Seerr (Mirrored Mode)..." -ForegroundColor Cyan

# Remove old rules if any
netsh advfirewall firewall delete rule name="Jellyfin TV" 2>$null
netsh advfirewall firewall delete rule name="Seerr TV" 2>$null

# Add permanent firewall inbound allow rules
netsh advfirewall firewall add rule name="Jellyfin TV" dir=in action=allow protocol=TCP localport=8096
netsh advfirewall firewall add rule name="Seerr TV" dir=in action=allow protocol=TCP localport=5055

# Clean up any leftover portproxy rules (since mirrored mode doesn't need them)
netsh interface portproxy delete v4tov4 listenport=8096 listenaddress=0.0.0.0 2>$null
netsh interface portproxy delete v4tov4 listenport=5055 listenaddress=0.0.0.0 2>$null

Write-Host "`nFirewall configured permanently!" -ForegroundColor Green
Write-Host "In Mirrored mode, NixOS directly uses your Windows IP on the local Wi-Fi network."
