#Requires -Version 5.1
# User-specific SDX build container setup (equivalent of normal_docker_helper.sh)

param(
    [switch]$Help,
    [switch]$DryRun,
    [string]$WorkPath,
    [string]$ToolPath,
    [string]$WslDistro = ""
)

# Path resolution: supports Windows, \\wsl$\..., and /mnt/wsl/... paths
function Resolve-DockerPath {
    param([string]$Path, [string]$Distro)

    # Already a \\wsl$\ UNC path -- Docker Desktop accepts it directly
    if ($Path -match '^\\\\wsl') { return $Path }

    # WSL2 Linux path (e.g. /mnt/wsl/PhysicalDrive1p1/work)
    # Convert to \\wsl$\<distro>\... so Docker Desktop on Windows can use it
    if ($Path -match '^/') {
        $winSlashes = $Path -replace '/', '\'
        return ('\\wsl$\' + $Distro + $winSlashes)
    }

    # Plain Windows path (C:\..., D:\...) -- pass through as-is
    return $Path
}

function Get-WslDistro {
    $raw = wsl --list --quiet 2>&1 |
           Where-Object { $_ -match '\w' } |
           Select-Object -First 1
    # wsl output can have null bytes on some versions
    return ($raw -replace '\x00', '' -replace '^\s+|\s+$', '')
}

function Print-Usage {
    Write-Host "normal_docker_helper.ps1 [options]"
    Write-Host "  -Help       : print help"
    Write-Host "  -DryRun     : print what will be done without executing"
    Write-Host "  -WorkPath   : working path to mount at /data/"
    Write-Host "  -ToolPath   : tool path to mount at /pkg/"
    Write-Host "  -WslDistro  : WSL2 distro name (auto-detected if omitted)"
    Write-Host ""
    Write-Host "PATH FORMATS SUPPORTED:"
    Write-Host "  Windows   : -WorkPath C:\work\sdx"
    Write-Host "  WSL2 UNC  : -WorkPath \\wsl$\Ubuntu\mnt\wsl\PhysicalDrive1p1\work"
    Write-Host "  WSL2 Linux: -WorkPath /mnt/wsl/PhysicalDrive1p1/work"
    Write-Host ""
    Write-Host "NOTE: For ext4 drives (D/E), run mount_linux_drives.ps1 as Admin first."
}

if ($Help) { Print-Usage; exit 0 }

if (-not $WorkPath -or -not $ToolPath) {
    Write-Host "Error: -WorkPath and -ToolPath are required."
    Write-Host ""
    Print-Usage
    exit 1
}

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path

# Linux usernames are lowercase; Windows usernames may be mixed case
$__USERNAME  = $env:USERNAME.ToLower()
# Windows has no UID/GID concept -- use Linux convention for first user
$__UID       = 1000
$__GID       = 1000

# Auto-detect WSL2 distro if not provided (needed for /mnt/wsl/... path conversion)
if (-not $WslDistro) {
    $WslDistro = Get-WslDistro
    if ($WslDistro) {
        Write-Host "Auto-detected WSL2 distro: '$WslDistro'"
    }
}

# Resolve paths -- supports Windows, \\wsl$\..., and /mnt/wsl/... formats
$WorkPath = Resolve-DockerPath -Path $WorkPath -Distro $WslDistro
$ToolPath = Resolve-DockerPath -Path $ToolPath -Distro $WslDistro
Write-Host "WorkPath resolved: $WorkPath"
Write-Host "ToolPath resolved: $ToolPath"

$DOCKER_PRV_NAME  = "build_sdx_jammy"
$DOCKER_CONTAINER = "${DOCKER_PRV_NAME}_${__USERNAME}"
$DOCKER_IMG       = "ghcr.io/cavli-wireless-public/sdx/jammy/owrt"
$DOCKER_IMG_TAG   = "latest"

# Pull latest base image
Write-Host "Pulling latest base image..."
docker pull "${DOCKER_IMG}:${DOCKER_IMG_TAG}"

# Remove stale container and per-user image
Write-Host "Cleaning up old container/image..."
docker stop $DOCKER_CONTAINER   2>&1 | Out-Null
docker rm   $DOCKER_CONTAINER   2>&1 | Out-Null
docker rmi  "${DOCKER_IMG}:${__USERNAME}" 2>&1 | Out-Null

# Generate Dockerfile from template
Write-Host "Generating Dockerfile for user '$__USERNAME'..."
$templatePath   = Join-Path $SCRIPT_DIR "Dockerfile.template"
$dockerfilePath = Join-Path $SCRIPT_DIR "Dockerfile"

(Get-Content $templatePath -Raw) `
    -replace '\{USERNAME\}',   $__USERNAME `
    -replace '\{UID\}',        $__UID `
    -replace '\{GID\}',        $__GID `
    -replace '\{DOCKER_TAG\}', $DOCKER_IMG_TAG |
    Set-Content -Path $dockerfilePath -Encoding UTF8

# Build user-specific image
Write-Host "Building image for user '$__USERNAME'..."
Push-Location $SCRIPT_DIR
docker build -t "${DOCKER_IMG}:${__USERNAME}" .
Pop-Location

# Optional SSH key mount
$extraVolumes = @()
$sshPath = Join-Path $env:USERPROFILE ".ssh"
if (Test-Path $sshPath -PathType Container) {
    $extraVolumes += "-v"
    $extraVolumes += "${sshPath}:/home/${__USERNAME}/.ssh"
    Write-Host "SSH keys found, will mount '$sshPath'."
} else {
    Write-Host "Warning: '$sshPath' not found, skipping SSH mount."
}

# Differences from Linux version:
#   --network host : not supported on Docker Desktop for Windows (removed)
#   /dev/bus/usb   : USB passthrough requires usbipd-win on Windows (removed)
#   /etc/localtime : replaced with -e TZ=...
#   /mnt           : not applicable on Windows (removed)
$dockerRunArgs = @(
    "run", "--name", $DOCKER_CONTAINER,
    "-dit", "--privileged",
    "-e", "TERM=xterm-256color",
    "-e", "TZ=Asia/Ho_Chi_Minh",
    "-u", $__USERNAME,
    "-h", $DOCKER_PRV_NAME,
    "--add-host", "${DOCKER_PRV_NAME}:127.0.0.1",
    "-v", "${WorkPath}:/data",
    "-v", "${ToolPath}/sectools:/pkg/sectools",
    "-v", "${ToolPath}/prebuilts:/pkg/prebuilts",
    "-v", "${ToolPath}/tools/sectools:/pkg/tools/sectools",
    "-v", "${ToolPath}/qct/software/HEXAGON_Tools:/pkg/qct/software/HEXAGON_Tools",
    "-v", "${ToolPath}/qct/software/arm:/pkg/qct/software/arm",
    "-v", "${ToolPath}/qct/software/llvm:/pkg/qct/software/llvm"
) + $extraVolumes + @("${DOCKER_IMG}:${__USERNAME}", "bash")

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - would execute:"
    Write-Host "  docker $($dockerRunArgs -join ' ')"
    exit 0
}

# Create and start container
Write-Host "Creating container '$DOCKER_CONTAINER'..."
& docker @dockerRunArgs

docker start $DOCKER_CONTAINER

# Setup rclone inside container
Write-Host "Setting up rclone..."
$rcloneTgz = Resolve-Path (Join-Path $SCRIPT_DIR "..\..\tools\rclone.tgz")
docker cp $rcloneTgz "${DOCKER_CONTAINER}:/home/rclone.tgz"
docker exec -u root $DOCKER_CONTAINER tar -xzf /home/rclone.tgz -C "/home/${__USERNAME}/"
docker exec -u root $DOCKER_CONTAINER cp "/home/${__USERNAME}/rclone/rclone" /usr/local/bin/rclone
docker exec -u root $DOCKER_CONTAINER chmod +x /usr/local/bin/rclone
docker exec -u root $DOCKER_CONTAINER cp "/home/${__USERNAME}/rclone/rclone_fw_share.conf" "/home/${__USERNAME}/"
docker exec -u root $DOCKER_CONTAINER bash -c "cat /home/${__USERNAME}/rclone/bash_aliases >> /home/${__USERNAME}/.bash_aliases"

docker stop $DOCKER_CONTAINER

Write-Host ""
Write-Host "DONE: Created container '$DOCKER_CONTAINER' for user '$__USERNAME'"
Write-Host "  Workspace : /data  (mapped from: $WorkPath)"
Write-Host "  Tools     : /pkg   (mapped from: $ToolPath)"
Write-Host ""
Write-Host "To start your build environment, run:"
Write-Host "  docker start -i $DOCKER_CONTAINER"
