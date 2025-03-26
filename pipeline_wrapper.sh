#!/bin/bash

# Ensure script fails on any error
set -e

# Get the absolute path of the script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Script directory: $SCRIPT_DIR"

# Change working directory to script directory
cd "$SCRIPT_DIR"
echo "Changed working directory to: $(pwd)"

# Set up logging
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="${LOG_DIR}/wrapper_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/wrapper_errors_${TIMESTAMP}.log"

# Redirect stdout and stderr to both console and log files
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$ERROR_LOG")

echo "Starting pipeline_wrapper.sh at $(date)"
echo "Running as user: $(whoami)"
echo "Current PATH: $PATH"

# Lock file to ensure single instance
LOCK_FILE="/tmp/pipeline_wrapper.lock"
LOCK_TIMEOUT=300  # 5 minutes timeout for stale locks

# Function to check if lock file is stale
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE")
        if ! kill -0 "$lock_pid" 2>/dev/null; then
            echo "Found stale lock file, removing..."
            rm -f "$LOCK_FILE"
            return 1
        fi
        local lock_time=$(stat -c %Y "$LOCK_FILE")
        local current_time=$(date +%s)
        if [ $((current_time - lock_time)) -gt $LOCK_TIMEOUT ]; then
            echo "Lock file is older than $LOCK_TIMEOUT seconds, removing..."
            rm -f "$LOCK_FILE"
            return 1
        fi
        return 0
    fi
    return 1
}

# Function to cleanup lock file
cleanup_lock() {
    echo "Cleaning up lock file..."
    rm -f "$LOCK_FILE"
    echo "Lock file cleaned up"
}

# Check if script is already running
if check_lock; then
    echo "Error: Another instance of pipeline_wrapper.sh is already running"
    exit 1
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed on script exit
trap 'cleanup_lock; exit' INT TERM EXIT

# Check if required arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_directory> <output_directory>"
    echo "Error: Missing required arguments"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

# Check if input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory does not exist: $INPUT_DIR"
    exit 1
fi

# Check if output directory exists, create if it doesn't
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Run the main pipeline script
echo "Starting workspace_na_pipeline.sh..."
if ! bash -c "./workspace_na_pipeline.sh \"$INPUT_DIR\" \"$OUTPUT_DIR\""; then
    echo "Error: workspace_na_pipeline.sh failed"
    exit 1
fi

echo "Pipeline completed successfully at $(date)" 