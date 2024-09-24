# Step 1: Force delete the Docker image if it exists
$IMAGE_NAME = "ghcr.io/cavli-wireless/sdx35/jammy/owrt:latest"

# Check if the image exists
if (docker images | Select-String -Pattern $IMAGE_NAME) {
    Write-Host "Image $IMAGE_NAME exists. Deleting..."
    docker rmi -f $IMAGE_NAME
}

# Step 2: Build a new Docker image
Write-Host "Building new Docker image from Dockerfile..."
Copy-Item Dockerfile.base Dockerfile
docker build -t $IMAGE_NAME .

# Output success message
Write-Host "Docker image $IMAGE_NAME built successfully!"