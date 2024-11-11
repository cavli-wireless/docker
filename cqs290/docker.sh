#!/bin/bash

print_usage()
{
    echo "normal_docker_helper.sh [options]"
    echo "  options:"
    echo "  -h: print help"
    echo "  -d: dry run: print what will be done"
    echo "  -s: use 'sudo' when it is needed"
    echo "  -w: working path to mount at /data/"
    echo "NOTE"
    echo "  This container base on ghcr.io/cavli-wireless/cqs290/build_cqs290:latest"
    echo "  Create user which refer from caller env ( result of whoami )"
    echo "  Mount and setup env to build"
    echo "  USER MUST PREPARE TOOLS BUILD"
}

# Parse command line arguments
while getopts "hdsw:t:" flag; do
  case $flag in
    d) DRYRUNCMD="echo";;
    s) SUDO="sudo";;
    w) WORK_PATH=$OPTARG;;
    *) print_usage; exit 1;;
  esac
done

shift $(( $OPTIND - 1 ))

__USERNAME=$(whoami)
__UID=$(id -u $1)
__GID=$(id -g $1)
DOCKER_CONTAINER=build_cqs290_$__USERNAME
#DOCKER_IMG=ghcr.io/cavli-wireless/cqs290/build_cqs290
DOCKER_IMG=ivando0209/build-os
DOCKER_IMG_TAG=latest

# login to github ghcr.io/cavli-wireless
# docker login ghcr.io/cavli-wireless
# Pull latest docker images
docker pull $DOCKER_IMG:$DOCKER_IMG_TAG
docker stop $DOCKER_CONTAINER 2> /dev/null
docker remove $DOCKER_CONTAINER 2> /dev/null

docker rmi $DOCKER_IMG:$__USERNAME 2> /dev/null

sed -e "s/{USERNAME}/$__USERNAME/g" \
    -e "s/{UID}/$__UID/g" \
    -e "s/{GID}/$__GID/g" \
    -e "s/{DOCKER_TAG}/$DOCKER_IMG_TAG/g" \
    Dockerfile.template > Dockerfile
docker build -t $DOCKER_IMG:$__USERNAME .

DIR_WHITELIST=(
  "/home/$__USERNAME/.ssh"
)

for path in "${DIR_WHITELIST[@]}"; do
  if [ -d "$path" ]; then
    CMD+=" -v $path:$path"
  else
    echo "Warning: Source path $path does not exist."
  fi
done

echo CMD=$CMD

docker run --name $DOCKER_CONTAINER \
    -dit --privileged --network host \
    -e "TERM=xterm-256color" \
    -u $__USERNAME -h $__USERNAME \
    --add-host ${__USERNAME}:127.0.0.1 \
    -v /dev/bus/usb/:/dev/bus/usb \
    -v /etc/localtime:/etc/localtime:ro \
    -v $WORK_PATH:$WORK_PATH \
    -v $WORK_PATH:/data/ \
    $CMD \
    $DOCKER_IMG:$__USERNAME bash -l
echo "Workspace: /data"
echo "Tools: /pkg"
echo "Let start it"
echo "docker start -i $DOCKER_CONTAINER"
