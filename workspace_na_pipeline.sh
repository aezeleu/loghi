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
LOG_FILE="${LOG_DIR}/pipeline_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/pipeline_errors_${TIMESTAMP}.log"

# Configuration options
REMOVE_PROCESSED_DIRS=true  # Set to false to keep processed directories in the input location
MAX_OPERATION_TIMEOUT=1800  # 30 minutes timeout for individual operations
CHECK_INTERVAL=30          # Check every 30 seconds

# Function to run command with timeout
run_with_timeout() {
    local cmd="$1"
    local timeout="$2"
    local operation="$3"
    local start_time=$(date +%s)
    
    # Start the command in background
    $cmd &
    local cmd_pid=$!
    
    # Monitor the command
    while kill -0 "$cmd_pid" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check if command has exceeded timeout
        if [ $elapsed -gt "$timeout" ]; then
            echo "Error: Operation '$operation' timed out after ${timeout} seconds" >> "$ERROR_LOG"
            kill -TERM "$cmd_pid" 2>/dev/null
            sleep 5
            
            # If still running, try SIGINT
            if kill -0 "$cmd_pid" 2>/dev/null; then
                kill -INT "$cmd_pid" 2>/dev/null
                sleep 5
            fi
            
            # If still running, force kill
            if kill -0 "$cmd_pid" 2>/dev/null; then
                kill -9 "$cmd_pid" 2>/dev/null
                echo "Force killed operation '$operation'" >> "$ERROR_LOG"
            fi
            
            return 1
        fi
        
        # Check if process is using CPU
        local cpu_usage=$(ps -p "$cmd_pid" -o %cpu | tail -n 1)
        if [ "$cpu_usage" = "0.0" ]; then
            echo "Warning: Operation '$operation' is not using CPU" >> "$ERROR_LOG"
        fi
        
        sleep $CHECK_INTERVAL
    done
    
    # Get the exit status
    wait $cmd_pid
    return $?
}

# Lock file to ensure single instance
LOCK_FILE="/tmp/workspace_na_pipeline.lock"
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

# Check if script is already running
if check_lock; then
    echo "Error: Another instance of the script is already running."
    echo "Lock file exists at: $LOCK_FILE"
    exit 1
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Function to cleanup lock file
cleanup_lock() {
    echo "Cleaning up lock file..."
    rm -f "$LOCK_FILE"
    echo "Lock file cleaned up"
}

# Ensure lock file is removed when script exits
trap 'cleanup_lock; cleanup_temp_workspace; exit' INT TERM EXIT

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

# Create temporary workspace
WSL_WORK_DIR="${SCRIPT_DIR}/temp_workspace"
mkdir -p "${WSL_WORK_DIR}"

# Define the full path to required scripts
NA_PIPELINE="${SCRIPT_DIR}/na-pipeline.sh"
XML2TEXT="${SCRIPT_DIR}/xml2text.sh"

# Verify scripts exist and are executable
for script in "$NA_PIPELINE" "$XML2TEXT"; do
    if [ ! -x "$script" ]; then
        echo "Error: Required script not found or not executable: $script"
        exit 1
    fi
done

# Function to check if a file needs processing
# Returns 0 if file needs processing, 1 if it doesn't
needs_processing() {
    local source_file="$1"
    local output_dir="$2"
    local filename=$(basename "$source_file")
    local extension="${filename##*.}"
    local name_without_ext="${filename%.*}"
    
    # Get source file modification time in seconds since epoch
    local source_mtime=$(stat -c %Y "$source_file")
    
    # Format current date for new files
    local current_date=$(date +"%d%m%Y")
    
    # Check if a file with the same base name exists in the output directory
    for dest_file in "$output_dir"/${name_without_ext}_*.$extension; do
        if [ -f "$dest_file" ]; then
            # Extract date from filename
            local dest_date=$(basename "$dest_file" | sed -E "s/${name_without_ext}_([0-9]{8})\.${extension}/\1/")
            
            # Get destination file modification time
            local dest_mtime=$(stat -c %Y "$dest_file")
            
            # If source file is newer than destination file, it needs processing
            if [ "$source_mtime" -gt "$dest_mtime" ]; then
                echo "Source file is newer than destination file. Processing required."
                return 0
            else
                echo "File already processed and up to date: $dest_file"
                return 1
            fi
        fi
    done
    
    # If no matching file found in destination, it needs processing
    echo "No matching file found in destination. Processing required."
    return 0
}

# Function to copy file with date suffix
copy_with_date_suffix() {
    local source_file="$1"
    local dest_dir="$2"
    local filename=$(basename "$source_file")
    local extension="${filename##*.}"
    local name_without_ext="${filename%.*}"
    local current_date=$(date +"%d%m%Y")
    
    # Create the new filename with date suffix
    local new_filename="${name_without_ext}_${current_date}.${extension}"
    
    # Create destination directory if it doesn't exist
    mkdir -p "${dest_dir}"
    
    # Copy the file with proper path handling
    echo "Copying from ${source_file} to ${dest_dir}/${new_filename}"
    if ! cp "${source_file}" "${dest_dir}/${new_filename}"; then
        echo "Error: Failed to copy ${source_file} to ${dest_dir}/${new_filename}"
        return 1
    fi
    
    echo "Successfully copied ${source_file} to ${dest_dir}/${new_filename}"
    return 0
}

# Function to cleanup temp workspace
cleanup_temp_workspace() {
    echo "Cleaning up temporary workspace..."
    if [ -d "$WSL_WORK_DIR" ]; then
        rm -rf "$WSL_WORK_DIR"
        echo "Temporary workspace cleaned up"
    fi
}

# Ensure cleanup happens on script exit
trap 'cleanup_temp_workspace' EXIT

# Process each directory in the input
for dir in "${INPUT_DIR}"/*/ ; do
    if [ ! -d "${dir}" ]; then
        continue
    fi
    
    dir_name=$(basename "${dir}")
    echo "Processing directory: ${dir_name}"
    
    # Create workspace directory
    workspace_dir="${WSL_WORK_DIR}/${dir_name}"
    mkdir -p "${workspace_dir}"
    
    # Copy files to workspace
    echo "Copying files from ${dir} to ${workspace_dir}"
    if ! cp -r "${dir}"* "${workspace_dir}/"; then
        echo "Error: Failed to copy directory ${dir} to workspace"
        continue
    fi
    
    # Create a sanitized directory name (replace spaces with underscores)
    safe_subdir_name=$(echo "$dir_name" | tr ' ' '_')
    
    # Create output directory for this subdirectory
    output_subdir="${OUTPUT_DIR}/${safe_subdir_name}"
    mkdir -p "${output_subdir}"
    
    # Check if files need processing
    process_directory=false
    for file in "${dir}"/*; do
        if [ -f "$file" ]; then
            if needs_processing "$file" "${output_subdir}"; then
                process_directory=true
                break
            fi
        fi
    done
    
    if [ "$process_directory" = true ]; then
        # Execute na-pipeline.sh on the copied directory with proper escaping
        echo "Executing na-pipeline.sh on: ${workspace_dir}"
        if ! run_with_timeout "${NA_PIPELINE} ${workspace_dir} ${workspace_dir}/output" "$MAX_OPERATION_TIMEOUT" "na-pipeline.sh"; then
            echo "Error: na-pipeline.sh failed for directory ${safe_subdir_name}"
            echo "$(date): Error in na-pipeline.sh for directory ${safe_subdir_name}" >> "$ERROR_LOG"
            continue
        fi

        # Check if page directory exists before attempting XML conversion
        if [ -d "${workspace_dir}/page" ]; then
            echo "Converting XML files to text using xml2text.sh..."
            if ! run_with_timeout "${XML2TEXT} ${workspace_dir}/page ${workspace_dir}/output" 900 "xml2text.sh"; then
                echo "Error: xml2text.sh failed for directory ${safe_subdir_name}"
                echo "$(date): Error in xml2text.sh for directory ${safe_subdir_name}" >> "$ERROR_LOG"
            else
                echo "XML to text conversion completed successfully"
            fi
        else
            echo "Note: No 'page' directory found in ${workspace_dir} - skipping XML conversion"
        fi

        # Copy output files to final destination with date suffix
        if [ -d "${workspace_dir}/output" ]; then
            # Copy each file with date suffix
            for file in "${workspace_dir}/output/"*; do
                if [ -f "$file" ]; then
                    copy_with_date_suffix "$file" "${output_subdir}"
                fi
            done
            
            echo "Copied output to ${output_subdir} with date suffix"
        else
            echo "Warning: Output directory not found in ${workspace_dir}"
        fi

        # Only remove processed directory if processing was successful
        if [ "$REMOVE_PROCESSED_DIRS" = true ] && [ -d "${workspace_dir}/output" ]; then
            if ! run_with_timeout "rm -rf \"${INPUT_DIR}/${dir_name}\"" 300 "Remove processed directory"; then
                echo "Warning: Failed to remove processed directory: ${INPUT_DIR}/${dir_name}"
            else
                echo "Removed processed directory from input: ${INPUT_DIR}/${dir_name}"
            fi
        else
            echo "Keeping processed directory in input: ${INPUT_DIR}/${dir_name}"
        fi
    else
        echo "Skipping directory ${dir_name} as all files are already processed and up to date"
    fi
done

# Clean up temp workspace at the end
cleanup_temp_workspace

echo "Processing completed."
