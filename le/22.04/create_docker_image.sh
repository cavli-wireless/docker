#!/bin/bash

# Step 1: Force delete the Docker image if it exists
IMAGE_NAME="ghcr.io/cavli-wireless-public/jammy/le:latest"

# Check if the image exists
if docker images | grep -q "$IMAGE_NAME"; then
    echo "Image $IMAGE_NAME exists. Deleting..."
    docker rmi -f $IMAGE_NAME
fi

# Step 2: Build a new Docker image
echo "Building new Docker image from Dockerfile..."
cp Dockerfile.base Dockerfile
docker build -t $IMAGE_NAME .

# Output success message
echo "Docker image $IMAGE_NAME built successfully!"
