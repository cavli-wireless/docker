#Requires -Version 5.1
# Mount Linux-formatted (ext4) drives D and E into WSL2
# Must be run as Administrator each time Windows restarts

param(
    [string]$Type = "ext4",
    [switch]$Unmount
)

# ── Known drive mapping (detected from Get-Partition) ────────────────────────
$DRIVES = @(
    @{ Letter = "E"; PhysicalDrive = "\\.\PhysicalDrive1"; Partition = 1; WslPath = "/mnt/wsl/PhysicalDrive1p1" },
    @{ Letter = "D"; PhysicalDrive = "\\.\PhysicalDrive0"; Partition = 2; WslPath = "/mnt/wsl/PhysicalDrive0p2" }
)

# ── Check Admin ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator."
    Write-Host "Right-click PowerShell -> 'Run as administrator', then run again."
    exit 1
}

foreach ($drive in $DRIVES) {
    if ($Unmount) {
        Write-Host "Unmounting drive $($drive.Letter): ($($drive.PhysicalDrive) partition $($drive.Partition))..."
        wsl --unmount $drive.PhysicalDrive
    } else {
        Write-Host "Mounting drive $($drive.Letter): ($($drive.PhysicalDrive) partition $($drive.Partition)) as $Type..."
        wsl --mount $drive.PhysicalDrive --partition $drive.Partition --type $Type

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  OK — accessible in WSL2 at: $($drive.WslPath)"
        } else {
            Write-Host "  ERROR: Failed to mount drive $($drive.Letter):"
        }
    }
}

if (-not $Unmount) {
    # Auto-detect WSL2 distro name
    $distro = wsl --list --quiet 2>$null | Where-Object { $_ -match '\w' } | Select-Object -First 1
    $distro = $distro -replace '\x00', '' -replace '^\s+|\s+$', ''

    Write-Host ""
    Write-Host "Drives mounted. Use these paths in normal_docker_helper.ps1:"
    foreach ($drive in $DRIVES) {
        $winPath = "\\wsl$\${distro}$($drive.WslPath -replace '/', '\')"
        Write-Host "  Drive $($drive.Letter): -> $winPath"
    }
    Write-Host ""
    Write-Host "Example:"
    $e = $DRIVES | Where-Object { $_.Letter -eq "E" }
    $distroClean = if ($distro) { $distro } else { "Ubuntu" }
    $exampleWin = "\\wsl$\${distroClean}$($e.WslPath -replace '/', '\')"
    Write-Host "  .\normal_docker_helper.ps1 -WorkPath `"$exampleWin\source`" -ToolPath `"$exampleWin\tools`""
}
