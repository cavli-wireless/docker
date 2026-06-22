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
    Write-Output "container_docker_helper.ps1 [options]"
    Write-Output "  Some important notes:"
    Write-Output "  The Docker images come with enough tools to allow you"
    Write-Output "  to compile boot, sysfs, and recovery."
    Write-Output "  If you want to build chip code, you must provide the"
    Write-Output "  path to the Qualcomm tool. There are two options:"
    Write-Output "    Option 1: Use the -t option (provide the path to the extracted folder)."
    Write-Output "    Option 2: Use the -f option (provide the path to the .7z file."
    Write-Output "    During setup, the script will copy the .7z file into the Docker"
    Write-Output "    container and extract it there)."
    Write-Output "  options:"
    Write-Output "  -h: print help"
    Write-Output "  -d: dry run: print what will be done"
    Write-Output "  -s: use 'sudo' when it is needed"
    Write-Output "  -w: working path to mount at /data/"
    Write-Output "  -t: tool path to mount at /pkg/"
    Write-Output "  -f: path to cqm220_buildtools.7z"
    Write-Output "NOTE"
    Write-Output "  This container base on ghcr.io/cavli-wireless-public/cqm220/jammy/owrt:latest"
    Write-Output "  Create user which refer from caller env ( result of whoami )"
    Write-Output "  Mount and setup env to build"
    Write-Output "  USER MUST PREPARE TOOLS BUILD"
}

${ToolPath} = ""
${FileToolPath} = ""
${WorkPath} = ""
${DryRunCmd} = ""
${Sudo} = ""

$optIndex = 0
while ($optIndex -lt $args.Length) {
    switch ($args[$optIndex]) {
        '-h' {
            Print-Usage
            exit 0
        }
        '-d' {
            ${DryRunCmd} = "Write-Output"
        }
        '-s' {
            ${Sudo} = "sudo"
        }
        '-w' {
            ${WorkPath} = $args[$optIndex + 1]
            $optIndex++
        }
        '-t' {
            ${ToolPath} = $args[$optIndex + 1]
            $optIndex++
        }
        '-f' {
            ${FileToolPath} = $args[$optIndex + 1]
            $optIndex++
        }
        default {
            Print-Usage
            exit 1
        }
    }
    $optIndex++
}

${Username} = "builder"
${Uid} = 1000
${Gid} = 1000
${DockerPrvName} = "build_cqm220_jammy"
${DockerContainer} = "${DockerPrvName}_${Username}"
${DockerImg} = "ghcr.io/cavli-wireless-public/cqm220/jammy/owrt"
${DockerImgTag} = "latest"

# Pull latest Docker images
docker pull "${DockerImg}:${DockerImgTag}"
docker stop ${DockerContainer} 2> $null
docker rm ${DockerContainer} 2> $null

docker rmi "${DockerImg}:${Username}" 2> $null

$dockerTemplate = @"
# Use the base image
FROM ghcr.io/cavli-wireless-public/cqm220/jammy/owrt:${DockerImgTag}

# Create a user group with GID ${Gid}
RUN groupadd -g ${Gid} ${Username}

# Create a user with UID ${Uid} and add to the group with GID ${Gid}
RUN useradd -u ${Uid} -g ${Gid} -m -s /bin/bash ${Username}
RUN usermod -aG sudo ${Username}

# Grant the user sudo privileges (optional)
RUN echo '${Username} ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set the default user to ${Username}
USER ${Username}

# Set the command to run /data/run.sh
CMD ["bash"]
"@

# Create a temporary Dockerfile
$dockerTemplate | Out-File -FilePath "Dockerfile"
docker build -t "${DockerImg}:${Username}" .
Remove-Item "Dockerfile"

$DirWhitelist = @(
    "/home/${Username}/.ssh"
)

$Cmd = ""
foreach ($path in $DirWhitelist) {
    if (Test-Path -Path $path) {
        $Cmd += " -v ${path}:${path}"
    } else {
        Write-Warning "Warning: Source path $path does not exist."
    }
}

# Check if both WORK_PATH and TOOL_PATH are set
if (-not [string]::IsNullOrEmpty(${FileToolPath}) -and -not [string]::IsNullOrEmpty(${ToolPath})) {
    Write-Output "Both FILE_TOOL_PATH and TOOL_PATH are set (please set one of them)"
    exit 1
}

if (-not [string]::IsNullOrEmpty(${ToolPath})) {
    $Cmd += " -v ${ToolPath}/qct/software/HEXAGON_Tools:/pkg/qct/software/HEXAGON_Tools "
    $Cmd += " -v ${ToolPath}/qct/software/arm:/pkg/qct/software/arm "
    $Cmd += " -v ${ToolPath}/qct/software/llvm:/pkg/qct/software/llvm "
} else {
    Write-Warning "Warning: Tool path is not set."
}

if (-not [string]::IsNullOrEmpty(${WorkPath})) {
    $Cmd += " -v ${WorkPath}:${WorkPath}"
} else {
    Write-Warning "Warning: Work path is not set."
}

Write-Output "CMD=$Cmd"

docker run --name ${DockerContainer} `
    -dit --privileged --network host `
    -e "TERM=xterm-256color" `
    -u ${Username} -h ${DockerPrvName} `
    --add-host "${DockerPrvName}:127.0.0.1" `
    -v "/dev/bus/usb/:/dev/bus/usb" `
    -v "/etc/localtime:/etc/localtime:ro" `
    $Cmd `
    "${DockerImg}:${Username}" bash

if (-not [string]::IsNullOrEmpty(${FileToolPath})) {
    docker start ${DockerContainer}
    docker cp ${FileToolPath} "${DockerContainer}:/pkg/cqm220_buildtools.7z"
    docker exec -u root ${DockerContainer} bash -c "cd /pkg/ ; 7z x cqm220_buildtools.7z -mmt=256"
    docker exec -u root ${DockerContainer} mv "/pkg/cqm220_buildtools/qct/software/HEXAGON_Tools" "/pkg/qct/software/"
    docker exec -u root ${DockerContainer} mv "/pkg/cqm220_buildtools/qct/software/arm" "/pkg/qct/software/"
    docker exec -u root ${DockerContainer} mv "/pkg/cqm220_buildtools/qct/software/llvm" "/pkg/qct/software/"
    docker exec -u root ${DockerContainer} rm -rf "/pkg/cqm220_buildtools*"
    docker exec -u root ${DockerContainer} chown "${Username}" -R "/pkg"
    docker stop ${DockerContainer}
}

Write-Output "DONE creating container ${DockerContainer} for user ${Username}"
Write-Output "Tools: /pkg"
Write-Output "Let's start it"
Write-Output "docker start -i ${DockerContainer}"
