#!/bin/bash
set -e

echo "Patching pipeline scripts for Docker wrapper compatibility..."

# Function to patch a file
patch_file() {
    local file="$1"
    local backup_file="${file}.bak"
    
    echo "Patching $file..."
    
    # Create backup
    cp "$file" "$backup_file"
    
    # Fix paths and make Docker socket available
    sed -i 's|docker run|docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock|g' "$file"
    
    # Update version to use environment variable if available
    sed -i 's|VERSION=1.3.7|VERSION=${LOGHI_VERSION:-1.3.7}|g' "$file"
    
    # Add support for external configuration
    sed -i '/^set -e/a\\\n# Load configuration if available\nif [ -f "$LOGHI_CONFIG_DIR/loghi.conf" ]; then\n    source "$LOGHI_CONFIG_DIR/loghi.conf"\nfi' "$file"
    
    echo "File $file patched successfully"
}

# Patch main pipeline scripts
for script in /app/na-pipeline.sh /app/na-pipeline-train.sh; do
    if [ -f "$script" ]; then
        patch_file "$script"
    else
        echo "Warning: Script $script not found, skipping..."
    fi
done

echo "All pipeline scripts patched successfully" 