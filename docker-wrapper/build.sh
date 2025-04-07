#!/bin/bash
set -e

echo "Building Loghi Docker Wrapper..."

# Create necessary directories
mkdir -p config data/input data/output logs models

# Copy default config files if they don't exist
if [ ! -f config/loghi.conf ]; then
    echo "Copying default configuration files..."
    cp config/loghi.conf.default config/loghi.conf
fi

# Build the Docker image
echo "Building Docker image..."
docker-compose build

echo "Build completed successfully."
echo ""
echo "You can now start the container with: docker-compose up -d"
echo "For more information, see the README.md file." 