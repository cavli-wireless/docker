#!/bin/bash

print_usage()
{
    echo "container_docker_helper.sh [options]"
    echo "  Some important notes:"
    echo "  The Docker images come with enough tools to allow you "
    echo "  to compile boot, sysfs, and recovery."
    echo "  If you want to build chip code, you must provide the "
    echo "  path to the Qualcomm tool. There are two options:"
    echo "    Option 1: Use the -t option (this requires the user "
    echo "    to extract the tool and provide the path to the extracted folder)."
    echo "    Option 2: Use the -f option (provide the path to the .7z file."
    echo "    During setup, the script will copy the .7z file into the Docker"
    echo "    container and extract it there)."
    echo "  options:"
    echo "  -h: print help"
    echo "  -d: dry run: print what will be done"
    echo "  -s: use 'sudo' when it is needed"
    echo "  -w: working path to mount at /data/"
    echo "  -t: tool path to mount at /pkg/"
    echo "  -f: path to cqm220_buildtools.7z"
    echo "NOTE"
    echo "  This container base on ghcr.io/cavli-wireless-public/cqm220/jammy/owrt:latest"
    echo "  Create user which refer from caller env ( result of whoami )"
    echo "  Mount and setup env to build"
    echo "  USER MUST PREPARE TOOLS BUILD"
}

TOOL_PATH=""
FILE_TOOL_PATH=""
WORK_PATH=""

# Parse command line arguments
while getopts "hdsw:t:f:" flag; do
  case $flag in
    d) DRYRUNCMD="echo";;
    s) SUDO="sudo";;
    w) WORK_PATH=$OPTARG;;
    t) TOOL_PATH=$OPTARG;;
    f) FILE_TOOL_PATH=$OPTARG;;
    *) print_usage; exit 1;;
  esac
done

shift $(( $OPTIND - 1 ))

__USERNAME=$(whoami)
__UID=$(id -u $1)
__GID=$(id -g $1)
DOCKER_PRV_NAME=build_cqm220_jammy
DOCKER_CONTAINER=${DOCKER_PRV_NAME}_${__USERNAME}
DOCKER_IMG=ghcr.io/cavli-wireless-public/cqm220/jammy/owrt
DOCKER_IMG_TAG=latest

# Pull latest docker_images
docker pull $DOCKER_IMG:$DOCKER_IMG_TAG
docker stop $DOCKER_CONTAINER 2> /dev/null
docker remove $DOCKER_CONTAINER 2> /dev/null

docker rmi $DOCKER_IMG:$__USERNAME 2> /dev/null

docker_template="
# Use the base image
FROM ghcr.io/cavli-wireless-public/cqm220/jammy/owrt:${DOCKER_IMG_TAG}

# Create a user group with GID ${__GID}
RUN groupadd -g ${__GID} ${__USERNAME}

# Create a user with UID ${__UID} and add to the group with GID ${__GID}
RUN useradd -u ${__UID} -g ${__GID} -m -s /bin/bash ${__USERNAME}
RUN usermod -aG sudo ${__USERNAME}

# Grant the user sudo privileges (optional)
RUN echo '${__USERNAME} ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set the default user to ${__USERNAME}
USER ${__USERNAME}

# Set the command to run /data/run.sh
CMD [\"bash\"]
"

# Create a temporary Dockerfile
echo "$docker_template" > Dockerfile
docker build -t $DOCKER_IMG:$__USERNAME .
rm Dockerfile

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

# Check if both WORK_PATH and TOOL_PATH are set
if [ ! -z "$FILE_TOOL_PATH" ] && [ ! -z "$TOOL_PATH" ]; then
  echo "Both FILE_TOOL_PATH and TOOL_PATH are set ( please set one of them )"
  exit 1
fi

if [ -z "$TOOL_PATH" ]; then
  echo "Warning: Tool path does not set."
else
  CMD+=" -v $TOOL_PATH/qct/software/HEXAGON_Tools:/pkg/qct/software/HEXAGON_Tools \
    -v $TOOL_PATH/qct/software/arm:/pkg/qct/software/arm \
    -v $TOOL_PATH/qct/software/llvm:/pkg/qct/software/llvm "
fi

if [ -z "$WORK_PATH" ]; then
  echo "Warning: Work path does not set."
else
  CMD+=" -v $WORK_PATH:$WORK_PATH"
fi

echo CMD=$CMD

docker run --name $DOCKER_CONTAINER \
    -dit --privileged --network host \
    -e "TERM=xterm-256color" \
    -u $__USERNAME -h $DOCKER_PRV_NAME \
    --add-host ${DOCKER_PRV_NAME}:127.0.0.1 \
    -v /dev/bus/usb/:/dev/bus/usb \
    -v /etc/localtime:/etc/localtime:ro \
    $CMD \
    $DOCKER_IMG:$__USERNAME bash

if [ -z "$FILE_TOOL_PATH" ]; then
  echo "Warning: File tool path does not set."
else
  docker start ${DOCKER_CONTAINER}
  docker cp ${FILE_TOOL_PATH} ${DOCKER_CONTAINER}:/pkg/cqm220_buildtools.7z
  docker exec -u root ${DOCKER_CONTAINER} bash -c "cd /pkg/ ; 7z x cqm220_buildtools.7z -mmt=256"
  docker exec -u root ${DOCKER_CONTAINER} mv /pkg/cqm220_buildtools/qct/software/HEXAGON_Tools /pkg/qct/software/
  docker exec -u root ${DOCKER_CONTAINER} mv /pkg/cqm220_buildtools/qct/software/arm /pkg/qct/software/
  docker exec -u root ${DOCKER_CONTAINER} mv /pkg/cqm220_buildtools/qct/software/llvm /pkg/qct/software/
  docker exec -u root ${DOCKER_CONTAINER} rm -rf /pkg/cqm220_buildtools*
  docker exec -u root ${DOCKER_CONTAINER} chown $__USERNAME -R /pkg
  docker stop ${DOCKER_CONTAINER}
fi

echo "DONE create container $DOCKER_CONTAINER for user $__USERNAME"
echo "Tools: /pkg"
echo "Let start it"
echo "docker start -i $DOCKER_CONTAINER"
