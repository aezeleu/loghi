#!/bin/bash

# Health check script for pipeline environment
# This script verifies the installation and configuration of the pipeline

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Docker images
check_docker_images() {
    echo "Checking Docker images..."
    local images=("loghi/docker.laypa" "loghi/docker.htr" "loghi/docker.loghi-tooling")
    local all_present=true
    
    for image in "${images[@]}"; do
        if docker images | grep -q "$image"; then
            echo "✓ Found Docker image: $image"
        else
            echo "✗ Missing Docker image: $image"
            all_present=false
        fi
    done
    
    return $([ "$all_present" = true ])
}

# Function to check directories
check_directories() {
    echo "Checking required directories..."
    local dirs=("$HOME/pipeline_logs" "fonts" "text" "output" "logs")
    local all_exist=true
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            echo "✓ Directory exists: $dir"
            # Check write permissions
            if [ -w "$dir" ]; then
                echo "  ✓ Write permission OK"
            else
                echo "  ✗ No write permission"
                all_exist=false
            fi
        else
            echo "✗ Missing directory: $dir"
            all_exist=false
        fi
    done
    
    return $([ "$all_exist" = true ])
}

# Function to check CRON configuration
check_cron() {
    echo "Checking CRON configuration..."
    if crontab -l 2>/dev/null | grep -q "pipeline_wrapper.sh"; then
        echo "✓ CRON job is configured"
        return 0
    else
        echo "✗ CRON job is not configured"
        return 1
    fi
}

# Function to check required tools
check_tools() {
    echo "Checking required tools..."
    local tools=("docker" "xmlstarlet" "git")
    local all_installed=true
    
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            echo "✓ Tool installed: $tool"
        else
            echo "✗ Missing tool: $tool"
            all_installed=false
        fi
    done
    
    return $([ "$all_installed" = true ])
}

# Function to check Docker permissions
check_docker_permissions() {
    echo "Checking Docker permissions..."
    if groups "$USER" | grep -q docker; then
        echo "✓ User has Docker permissions"
        return 0
    else
        echo "✗ User lacks Docker permissions"
        return 1
    fi
}

# Main health check
echo "Starting pipeline health check..."
echo "================================"

# Initialize status
status=0

# Run all checks
check_tools || status=1
check_docker_permissions || status=1
check_docker_images || status=1
check_directories || status=1
check_cron || status=1

echo "================================"
if [ $status -eq 0 ]; then
    echo "✓ All checks passed! Pipeline environment is healthy."
    exit 0
else
    echo "✗ Some checks failed. Please review the issues above."
    exit 1
fi
