#!/bin/bash
set -e

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

# Check if the container is already running
if docker ps | grep -q loghi-wrapper; then
    echo "Loghi Docker Wrapper is already running."
    echo "You can execute commands with: docker exec loghi-wrapper <command>"
    echo "To stop the container: docker-compose down"
    exit 0
fi

# Start the container
echo "Starting Loghi Docker Wrapper..."
docker-compose up -d

# Check if the container started successfully
if docker ps | grep -q loghi-wrapper; then
    echo "Loghi Docker Wrapper started successfully."
    echo "You can execute commands with: docker exec loghi-wrapper <command>"
    echo "To stop the container: docker-compose down"
else
    echo "Error: Failed to start Loghi Docker Wrapper."
    echo "Check the logs with: docker-compose logs"
    exit 1
fi 