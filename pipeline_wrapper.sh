#!/bin/bash

# Global Configuration
WORKSPACE_DIR="/home/default/Companies/Archive/loghi-main"
LOG_DIR="$HOME/pipeline_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOCK_FILE="/tmp/workspace_na_pipeline.lock"

# Pipeline Configuration
REMOVE_PROCESSED_DIRS=false
STOPONERROR=1
BASELINELAYPA=1
HTRLOGHI=1
RECALCULATEREADINGORDER=1
RECALCULATEREADINGORDERBORDERMARGIN=50
RECALCULATEREADINGORDERCLEANBORDERS=0
RECALCULATEREADINGORDERTHREADS=4
DETECTLANGUAGE=1
SPLITWORDS=1
BEAMWIDTH=1
GPU=0

# Docker Configuration
VERSION=1.3.7
DOCKERLOGHITOOLING="loghi/docker.loghi-tooling:$VERSION"
DOCKERLAYPA="loghi/docker.laypa:$VERSION"
DOCKERLOGHIHTR="loghi/docker.htr:$VERSION"
USE2013NAMESPACE=" -use_2013_namespace "

# Model Paths
BASEDIR="$WORKSPACE_DIR"
LAYPAMODEL="$BASEDIR/laypa/general/baseline/config.yaml"
LAYPAMODELWEIGHTS="$BASEDIR/laypa/general/baseline/model_best_mIoU.pth"
HTRLOGHIMODEL="$BASEDIR/loghi-htr/generic-2023-02-15"

# Export variables for child scripts
export BASEDIR
export LAYPAMODEL
export LAYPAMODELWEIGHTS
export HTRLOGHIMODEL
export STOPONERROR
export BASELINELAYPA
export HTRLOGHI
export RECALCULATEREADINGORDER
export RECALCULATEREADINGORDERBORDERMARGIN
export RECALCULATEREADINGORDERCLEANBORDERS
export RECALCULATEREADINGORDERTHREADS
export DETECTLANGUAGE
export SPLITWORDS
export BEAMWIDTH
export GPU
export DOCKERLOGHITOOLING
export DOCKERLAYPA
export DOCKERLOGHIHTR
export USE2013NAMESPACE

# Create log directory
mkdir -p "$LOG_DIR"

# Check if script is already running
if [ -f "$LOCK_FILE" ]; then
    echo "Error: Another instance of the script is already running." >> "$LOG_DIR/error_$TIMESTAMP.log"
    echo "Lock file exists at: $LOCK_FILE" >> "$LOG_DIR/error_$TIMESTAMP.log"
    exit 1
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed when script exits
trap "rm -f $LOCK_FILE; exit" INT TERM EXIT

# Change to workspace directory
cd "$WORKSPACE_DIR" || {
    echo "Error: Cannot change to workspace directory" >> "$LOG_DIR/error_$TIMESTAMP.log"
    exit 1
}

# Check dependencies
if ! command -v xmlstarlet &> /dev/null; then
    echo "Error: xmlstarlet is not installed" >> "$LOG_DIR/error_$TIMESTAMP.log"
    exit 1
fi

# Pull latest changes
echo "Pulling latest changes..." >> "$LOG_DIR/git_pull_$TIMESTAMP.log"
git pull origin main >> "$LOG_DIR/git_pull_$TIMESTAMP.log" 2>&1

# Run health check
if [ -f "./health-check.sh" ]; then
    echo "Running health check..." >> "$LOG_DIR/health_check_$TIMESTAMP.log"
    ./health-check.sh >> "$LOG_DIR/health_check_$TIMESTAMP.log" 2>&1
fi

# Process pipeline
echo "Starting pipeline processing..." >> "$LOG_DIR/pipeline_$TIMESTAMP.log"
./workspace_na_pipeline.sh "$1" "$2" >> "$LOG_DIR/pipeline_$TIMESTAMP.log" 2>&1

# Generate summary
echo "Generating summary..." >> "$LOG_DIR/summary_$TIMESTAMP.log"
git log --since="2 minutes ago" --pretty=format:"%h - %s (%cr)" >> "$LOG_DIR/summary_$TIMESTAMP.log"

# Cleanup
rm -f "$LOCK_FILE"

echo "Pipeline completed successfully" >> "$LOG_DIR/pipeline_$TIMESTAMP.log" 