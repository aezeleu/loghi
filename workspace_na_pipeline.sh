#!/bin/bash

echo "Starting workspace_na_pipeline.sh"
# Change working directory to script directory
cd "$(dirname "$0")"

# Lock file to ensure single instance
LOCK_FILE="/tmp/workspace_na_pipeline.lock"

# Check if script is already running
if [ -f "$LOCK_FILE" ]; then
    echo "Error: Another instance of the script is already running."
    echo "Lock file exists at: $LOCK_FILE"
    exit 1
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed when script exits
trap "rm -f $LOCK_FILE; exit" INT TERM EXIT

# # Add a 5 minute delay (for quick testing)
# echo "Waiting for 5 minutes..."
# sleep 300
# exit 0

# Accept parameters from command line
INPUT_DIR="$1"
OUTPUT_DIR="$2"

# Check for the presence of input parameters
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Error: INPUT_DIR and OUTPUT_DIR must be specified."
    echo "Usage: $0 <INPUT_DIR> <OUTPUT_DIR>"
    exit 1
fi

# Check if input directory exists and is accessible
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist or is not accessible."
    echo "Please ensure the Google Drive is properly mounted in WSL."
    exit 1
fi

# Check if output directory path is writable
if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
    echo "Error: Cannot create or access output directory '$OUTPUT_DIR'."
    echo "Please ensure the Google Drive is properly mounted in WSL."
    exit 1
fi

# Create OUTPUT_DIR if it does not exist
mkdir -p "$OUTPUT_DIR"

# Define WSL work directory
WSL_WORK_DIR="$(pwd)/temp_workspace"
echo "WSL_WORK_DIR: $WSL_WORK_DIR"
mkdir -p "$WSL_WORK_DIR"

# Process all subdirectories in INPUT_DIR
for subdir in "$INPUT_DIR"/*/ ; do
    if [ -d "$subdir" ]; then
        subdir_name=$(basename "$subdir")
        echo "Processing directory: $subdir_name"

        # Create a sanitized directory name (replace spaces with underscores)
        safe_subdir_name=$(echo "$subdir_name" | tr ' ' '_')
        
        # Copy subdirectory to WSL work directory with sanitized name
        cp -r "$subdir" "$WSL_WORK_DIR/$safe_subdir_name"
        echo "Copied $subdir to $WSL_WORK_DIR/$safe_subdir_name"

        # Execute na-pipeline.sh on the copied directory (with quotes to handle spaces)
        ./na-pipeline.sh "$WSL_WORK_DIR/$safe_subdir_name" "$WSL_WORK_DIR/$safe_subdir_name/output"

        # Remove processed subdirectory from input directory
        rm -rf "$INPUT_DIR/$subdir_name"
        echo "Removed processed directory from input: $INPUT_DIR/$subdir_name"

        # Convert XML files to text files using xml2text.sh script
        ./xml2text.sh "$WSL_WORK_DIR/$safe_subdir_name/output" "$WSL_WORK_DIR/$safe_subdir_name/output"

        # Copy output directory to final destination
        if [ -d "$WSL_WORK_DIR/$safe_subdir_name/output" ]; then
            mkdir -p "$OUTPUT_DIR/$safe_subdir_name"
            cp -r "$WSL_WORK_DIR/$safe_subdir_name/output/"* "$OUTPUT_DIR/$safe_subdir_name/"
            echo "Copied output to $OUTPUT_DIR/$safe_subdir_name"
        else
            echo "Warning: Output directory not found in $WSL_WORK_DIR/$safe_subdir_name"
        fi

        # Clean up temporary working directory for this subdirectory
        echo "Cleaning up temporary directory: $WSL_WORK_DIR/$safe_subdir_name"
        rm -rf "$WSL_WORK_DIR/$safe_subdir_name"
    fi
done

echo "Processing completed."
