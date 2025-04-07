#!/bin/bash
set -e

# Source configuration file
CONFIG_FILE="${LOGHI_CONFIG_DIR}/loghi.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# List of scripts to update
SCRIPTS=(
    "/app/na-pipeline.sh"
    "/app/na-pipeline-train.sh"
    "/app/pipeline_wrapper.sh"
    "/app/generate-images.sh"
    "/app/workspace_na_pipeline.sh"
)

# Create backup directory
BACKUP_DIR="/app/backup"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "Updating scripts with configuration values..."

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo "Processing $script..."
        
        # Create backup
        cp "$script" "$BACKUP_DIR/$(basename "$script")_$TIMESTAMP"
        
        # Update Docker image versions
        sed -i "s|DOCKERLOGHITOOLING=loghi/docker.loghi-tooling:[0-9.]*|DOCKERLOGHITOOLING=$DOCKER_LOGHI_TOOLING|g" "$script"
        sed -i "s|DOCKERLAYPA=loghi/docker.laypa:[0-9.]*|DOCKERLAYPA=$DOCKER_LAYPA|g" "$script"
        sed -i "s|DOCKERLOGHIHTR=loghi/docker.htr:[0-9.]*|DOCKERLOGHIHTR=$DOCKER_HTR|g" "$script"
        
        # Update base directory
        sed -i "s|BASEDIR=.*|BASEDIR=$BASEDIR|g" "$script"
        
        # Update model paths
        sed -i "s|LAYPAMODEL=.*|LAYPAMODEL=$LAYPAMODEL|g" "$script"
        sed -i "s|LAYPAMODELWEIGHTS=.*|LAYPAMODELWEIGHTS=$LAYPAMODELWEIGHTS|g" "$script"
        sed -i "s|HTRLOGHIMODEL=.*|HTRLOGHIMODEL=$HTRLOGHIMODEL|g" "$script"
        
        # Update feature flags
        sed -i "s|BASELINELAYPA=.*|BASELINELAYPA=$BASELINELAYPA|g" "$script"
        sed -i "s|HTRLOGHI=.*|HTRLOGHI=$HTRLOGHI|g" "$script"
        sed -i "s|RECALCULATEREADINGORDER=.*|RECALCULATEREADINGORDER=$RECALCULATEREADINGORDER|g" "$script"
        sed -i "s|DETECTLANGUAGE=.*|DETECTLANGUAGE=$DETECTLANGUAGE|g" "$script"
        sed -i "s|SPLITWORDS=.*|SPLITWORDS=$SPLITWORDS|g" "$script"
        
        # Update performance settings
        sed -i "s|RECALCULATEREADINGORDERBORDERMARGIN=.*|RECALCULATEREADINGORDERBORDERMARGIN=$RECALCULATEREADINGORDERBORDERMARGIN|g" "$script"
        sed -i "s|RECALCULATEREADINGORDERCLEANBORDERS=.*|RECALCULATEREADINGORDERCLEANBORDERS=$RECALCULATEREADINGORDERCLEANBORDERS|g" "$script"
        sed -i "s|RECALCULATEREADINGORDERTHREADS=.*|RECALCULATEREADINGORDERTHREADS=$RECALCULATEREADINGORDERTHREADS|g" "$script"
        sed -i "s|BEAMWIDTH=.*|BEAMWIDTH=$BEAMWIDTH|g" "$script"
        sed -i "s|GPU=.*|GPU=$GPU|g" "$script"
        sed -i "s|STOPONERROR=.*|STOPONERROR=$STOPONERROR|g" "$script"
        
        # Update namespace settings
        sed -i "s|USE2013NAMESPACE=.*|USE2013NAMESPACE=\"$USE2013NAMESPACE\"|g" "$script"
        
        echo "Script $script updated successfully"
    else
        echo "Warning: Script $script not found, skipping..."
    fi
done

echo "All scripts updated successfully" 