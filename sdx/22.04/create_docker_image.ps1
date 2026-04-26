#Requires -Version 5.1
# Build the base SDX Docker image (equivalent of create_docker_image.sh)

$IMAGE_NAME = "ghcr.io/cavli-wireless-public/sdx/jammy/owrt:latest"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $SCRIPT_DIR

# Delete existing image if it exists
$existing = & docker images --format "{{.Repository}}:{{.Tag}}" 2>&1 | Where-Object { $_ -eq $IMAGE_NAME }
if ($existing) {
    Write-Host "Image $IMAGE_NAME exists. Deleting..."
    docker rmi -f $IMAGE_NAME
}

# Build new image
Write-Host "Building new Docker image from Dockerfile..."
Copy-Item -Path "Dockerfile.base" -Destination "Dockerfile" -Force
docker build -t $IMAGE_NAME .

Pop-Location
Write-Host "Docker image $IMAGE_NAME built successfully!"
