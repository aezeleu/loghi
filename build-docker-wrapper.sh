#!/bin/bash
set -e

echo "Building Loghi Docker Wrapper..."

# Navigate to the docker-wrapper directory
cd $(dirname "$0")/docker-wrapper

# Create necessary directories
mkdir -p config data/input data/output logs models

# Copy default config files if they don't exist
if [ ! -f config/loghi.conf ]; then
    echo "Copying default configuration files..."
    cp config/loghi.conf.default config/loghi.conf
fi

# Build the Docker image with the parent directory as context
echo "Building Docker image with proper context..."
docker build -t loghi-wrapper:latest -f Dockerfile ..

echo "Build completed successfully."
echo ""
echo "You can now start the container with: cd docker-wrapper && docker-compose up -d"
echo "For more information, see the docker-wrapper/README.md file." 