${Username} = "buider"
${DockerPrvName} = "build_cqm220_sdk_jammy"
${DockerContainer} = "${DockerPrvName}_${Username}"
${DockerImg} = "ghcr.io/cavli-wireless-public/cqm220/jammy/owrt"
${DockerImgTag} = "builder"
${DOCKER_PRV_NAME} = "build_cqm220_jammy"

# Pull latest Docker images
docker pull "${DockerImg}:${DockerImgTag}"
docker stop ${DockerContainer} 2> $null
docker rm ${DockerContainer} 2> $null

docker run --name ${DockerContainer} `
    -dit --privileged --network host `
    -e "TERM=xterm-256color" -h ${DOCKER_PRV_NAME} `
    --add-host ${DOCKER_PRV_NAME}:127.0.0.1 `
    $Cmd `
    "${DockerImg}:${DockerImgTag}" bash

Write-Output "DONE creating container ${DockerContainer} for user ${Username}"
Write-Output "Tools: /pkg"
Write-Output "Let's start it"
Write-Output "docker start -i ${DockerContainer}"
