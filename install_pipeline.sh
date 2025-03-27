#!/bin/bash

# Installation script for pipeline environment

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package
install_package() {
    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y "$1"
    elif command_exists yum; then
        sudo yum install -y "$1"
    else
        echo "Error: Unsupported package manager"
        exit 1
    fi
}

# Function to check and create directory
create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo "Created directory: $1"
    else
        echo "Directory exists: $1"
    fi
}

# Function to set up logging
setup_logging() {
    local log_dir="$HOME/pipeline_logs"
    create_directory "$log_dir"
    chmod 755 "$log_dir"
}

# Function to check and install dependencies
install_dependencies() {
    echo "Checking and installing dependencies..."
    
    # Check and install xmlstarlet
    if ! command_exists xmlstarlet; then
        echo "Installing xmlstarlet..."
        install_package "xmlstarlet"
    fi
    
    # Check and install git
    if ! command_exists git; then
        echo "Installing git..."
        install_package "git"
    fi
    
    # Check and install Docker
    if ! command_exists docker; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
    fi
    
    # Add user to docker group
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        echo "Added user to docker group. Please log out and back in for changes to take effect."
    fi
}

# Function to set up CRON job
setup_cron() {
    echo "Setting up CRON job..."
    
    # Create CRON entry
    local cron_entry="*/2 * * * * $WORKSPACE_DIR/pipeline_wrapper.sh"
    
    # Add to crontab if not already present
    if ! crontab -l 2>/dev/null | grep -q "$cron_entry"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        echo "Added CRON job"
    else
        echo "CRON job already exists"
    fi
    
    # Add log rotation
    local log_rotation="0 0 * * * find $HOME/pipeline_logs -type f -mtime +7 -exec rm {} \;"
    if ! crontab -l 2>/dev/null | grep -q "$log_rotation"; then
        (crontab -l 2>/dev/null; echo "$log_rotation") | crontab -
        echo "Added log rotation"
    fi
}

# Function to set up permissions
setup_permissions() {
    echo "Setting up permissions..."
    
    # Make scripts executable
    chmod +x "$WORKSPACE_DIR/pipeline_wrapper.sh"
    chmod +x "$WORKSPACE_DIR/health-check.sh"
    chmod +x "$WORKSPACE_DIR/workspace_na_pipeline.sh"
    chmod +x "$WORKSPACE_DIR/xml2text.sh"
    chmod +x "$WORKSPACE_DIR/na-pipeline.sh"
}

# Main installation
echo "Starting pipeline installation..."

# Set workspace directory
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install dependencies
install_dependencies

# Set up logging
setup_logging

# Set up permissions
setup_permissions

# Set up CRON job
setup_cron

echo "Running health check..."
if "$WORKSPACE_DIR/health-check.sh"; then
    echo "Installation completed successfully!"
    echo "Please ensure all required model files are present in the correct locations."
    echo "You may need to log out and back in for all changes to take effect."
else
    echo "Installation completed with warnings. Please review the health check output above."
    exit 1
fi 