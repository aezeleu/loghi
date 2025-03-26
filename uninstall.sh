#!/bin/bash

# Uninstall script for Loghi project environment
# This script will clean up Docker containers, images, and project files

echo "Starting Loghi project uninstallation..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Docker is running
check_docker() {
    if ! command_exists docker; then
        echo "Docker is not installed. Skipping Docker cleanup."
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon is not running. Skipping Docker cleanup."
        return 1
    fi
    
    return 0
}

# Function to stop and remove containers
cleanup_containers() {
    echo "Stopping and removing Loghi containers..."
    docker ps -a | grep loghi | awk '{print $1}' | xargs -r docker stop
    docker ps -a | grep loghi | awk '{print $1}' | xargs -r docker rm
}

# Function to remove images
cleanup_images() {
    echo "Removing Loghi Docker images..."
    docker images | grep loghi | awk '{print $3}' | xargs -r docker rmi -f
}

# Function to clean up project files
cleanup_project_files() {
    echo "Cleaning up project files..."
    
    # Remove generated directories
    rm -rf output/
    rm -rf test_input/
    rm -rf test_output/
    rm -rf temp_workspace/
    rm -rf logs/
    
    # Remove generated files
    rm -f *.lock
    rm -f *.log
    
    # Remove Docker-related files
    rm -f docker-compose.yml
    rm -f Dockerfile*
    
    # Remove test data
    rm -rf fonts/
    rm -rf text/
}

# Main uninstallation process
echo "Starting cleanup process..."

# Check and cleanup Docker if available
if check_docker; then
    cleanup_containers
    cleanup_images
fi

# Clean up project files
cleanup_project_files

# Remove the uninstall script itself
echo "Uninstallation complete. Removing uninstall script..."
rm -f "$0"

echo "Loghi project environment has been uninstalled successfully." 