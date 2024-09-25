# Parse command line arguments
param(
    [Parameter()]
    [string]$d,
    [Parameter()]
    [switch]$s,
    [Parameter()]
    [string]$t,
    [Parameter()]
    [switch]$h
)

function Print-Usage {
    Write-Host "normal_docker_helper.ps1 [options]"
    Write-Host "  options:"
    Write-Host "  -h: print help"
    Write-Host "  -d: dry run: print what will be done"
    Write-Host "  -s: use 'sudo' when it is needed"
    Write-Host "  -w: working path to mount at /data/"
    Write-Host "  -t: tool path to mount at /pkg/"
    Write-Host "NOTE"
    Write-Host "  This container is based on ghcr.io/cavli-wireless/sdx35/jammy/owrt:latest"
    Write-Host "  Creates user which refers from caller environment (result of whoami)"
    Write-Host "  Mount and setup env to build"
    Write-Host "  USER MUST PREPARE TOOLS BUILD"
}

# Default values
${DRYRUNCMD} = ""
${SUDO} = ""
${TOOL_PATH} = ""

if ($h) {
    Print-Usage
    exit
}

if ($d) {
    ${DRYRUNCMD} = "Write-Host"
}

if ($s) {
    ${SUDO} = "sudo"
}


if ($t) {
    ${TOOL_PATH} = $t
}

# Get user and group info
$__USERNAME = "builder"
$__UID = 1000
$__GID = 1000
${DOCKER_PRV_NAME} = "build_sdx35_jammy"
${DOCKER_CONTAINER} = "${DOCKER_PRV_NAME}_$__USERNAME"
${DOCKER_IMG} = "ghcr.io/cavli-wireless/sdx35/jammy/owrt"
${DOCKER_IMG_TAG} = "latest"

# Login and pull latest Docker image
docker pull "${DOCKER_IMG}:${DOCKER_IMG_TAG}"
docker stop ${DOCKER_CONTAINER} 2> $null
docker rm ${DOCKER_CONTAINER} 2> $null

docker rmi "${DOCKER_IMG}:$__USERNAME" 2> $null

# Update Dockerfile based on template
(Get-Content Dockerfile.template) -replace '{USERNAME}', $__USERNAME -replace '{UID}', $__UID -replace '{GID}', $__GID -replace '{DOCKER_TAG}', ${DOCKER_IMG_TAG} | Set-Content Dockerfile

# Build new Docker image
docker build -t "${DOCKER_IMG}:$__USERNAME" .

# Run Docker container with the required mounts
docker run --name ${DOCKER_CONTAINER} `
    -dit --privileged --network host `
    -e "TERM=xterm-256color" `
    -u $__USERNAME -h ${DOCKER_PRV_NAME} `
    --add-host "${DOCKER_PRV_NAME}:127.0.0.1" `
    -v /dev/bus/usb/:/dev/bus/usb `
    -v /etc/localtime:/etc/localtime:ro `
    "${DOCKER_IMG}:$__USERNAME" bash

# Start and configure Docker container
docker start ${DOCKER_CONTAINER}
docker exec -u $__USERNAME ${DOCKER_CONTAINER} git config --global user.name "firmware"
docker exec -u $__USERNAME ${DOCKER_CONTAINER} git config --global user.email "firmware@cavliwireless.com"
docker cp ../../tools/rclone.tgz ${DOCKER_CONTAINER}:/home/rclone.tgz
docker exec -u root ${DOCKER_CONTAINER} tar -xzf /home/rclone.tgz -C /home/$__USERNAME/
docker exec -u root ${DOCKER_CONTAINER} cp /home/$__USERNAME/rclone/rclone /usr/local/bin/rclone
docker exec -u root ${DOCKER_CONTAINER} chmod +x /usr/local/bin/rclone
docker exec -u root ${DOCKER_CONTAINER} cp /home/$__USERNAME/rclone/rclone_fw_share.conf /home/$__USERNAME
docker exec -u root ${DOCKER_CONTAINER} bash -c "cat /home/$__USERNAME/rclone/bash_aliases >> /home/$__USERNAME/.bash_aliases"
docker exec -u root ${DOCKER_CONTAINER} mkdir /pkg/tmp
docker cp ${TOOL_PATH} ${DOCKER_CONTAINER}:/pkg/tmp/cavli_sdx35_buildtools.7z
docker exec -u root ${DOCKER_CONTAINER} bash -c "cd /pkg/tmp/ ; 7z x cavli_sdx35_buildtools.7z -mmt=256"
docker exec -u root ${DOCKER_CONTAINER} mv /pkg/tmp/sectools /pkg/
docker exec -u root ${DOCKER_CONTAINER} mv /pkg/tmp/prebuilts /pkg/
docker exec -u root ${DOCKER_CONTAINER} mv /pkg/tmp/tools/sectools /pkg/tools/
docker exec -u root ${DOCKER_CONTAINER} mv /pkg/tmp/qct/software/HEXAGON_Tools /pkg/qct/software/
docker exec -u root ${DOCKER_CONTAINER} mv /pkg/tmp/qct/software/arm /pkg/qct/software/
docker exec -u root ${DOCKER_CONTAINER} mv /pkg/tmp/qct/software/llvm /pkg/qct/software/
docker exec -u root ${DOCKER_CONTAINER} rm -rf /pkg/tmp
docker exec -u root ${DOCKER_CONTAINER} chown builder -R /pkg

if (Test-Path "~/.ssh") {
    docker exec -u $__USERNAME ${DOCKER_CONTAINER} mkdir /home/$__USERNAME/.ssh -p
    docker cp ${home}/.ssh/config ${DOCKER_CONTAINER}:/home/$__USERNAME/.ssh/
    docker cp ${home}/.ssh/id_rsa ${DOCKER_CONTAINER}:/home/$__USERNAME/.ssh/
    docker cp ${home}/.ssh/id_rsa.pub ${DOCKER_CONTAINER}:/home/$__USERNAME/.ssh/
}
docker stop ${DOCKER_CONTAINER}

Write-Host "DONE creating container ${DOCKER_CONTAINER} for user $__USERNAME"
Write-Host "Workspace: /data"
Write-Host "Tools: /pkg"
Write-Host "To start the container: docker start -i ${DOCKER_CONTAINER}"
