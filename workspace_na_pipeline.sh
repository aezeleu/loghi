#!/bin/bash

# Ensure script fails on any error
set -e

# --- Script Setup & Configuration ---
# Get the absolute path of the script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Script directory: $SCRIPT_DIR"

# Change working directory to script directory
cd "$SCRIPT_DIR"
echo "Changed working directory to: $(pwd)"

# --- DinD Specific Path Configuration ---
# Base for temporary processing within the wrapper container's filesystem.
# This path uses a named volume from docker-compose.yml (e.g., loghi_wrapper_tmp for /tmp).
PROCESSING_BASE_INSIDE_WRAPPER="/tmp" # Or use "/app/temp_workspace"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
CURRENT_SCRIPT_PID=$$ # PID of this script instance for unique directory naming

# Define unique temporary workspace for this pipeline run
WSL_WORK_DIR="${PROCESSING_BASE_INSIDE_WRAPPER}/pipeline_run_${TIMESTAMP}_${CURRENT_SCRIPT_PID}"

# Logging configuration (logs also go to a named volume inside the wrapper)
LOG_DIR_BASE="/app/logs" # Uses 'loghi_wrapper_logs' volume
LOG_DIR="${LOG_DIR_BASE}/run_${TIMESTAMP}_${CURRENT_SCRIPT_PID}"

# Create log directory (should be writable by the 'ubuntu' user running this script)
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/pipeline.log"
ERROR_LOG="${LOG_DIR}/pipeline_errors.log"

# Initial log entries
echo "--- Pipeline Execution Start: $(date) ---" | tee -a "$LOG_FILE"
echo "INFO: Running in Docker-in-Docker (DinD) mode." | tee -a "$LOG_FILE"
echo "INFO: Pipeline temporary workspace (WSL_WORK_DIR): ${WSL_WORK_DIR}" | tee -a "$LOG_FILE"
echo "INFO: Logging to: ${LOG_FILE} and ${ERROR_LOG}" | tee -a "$LOG_FILE"
echo "INFO: Current user: $(whoami) (UID: $(id -u), GID: $(id -g))" | tee -a "$LOG_FILE"
echo "INFO: Docker CLI version (talking to internal daemon): $(docker --version 2>/dev/null || echo 'docker CLI not found or error')" | tee -a "$LOG_FILE"

# Ensure the main temporary workspace directory exists
mkdir -p "${WSL_WORK_DIR}"
# Permissions: The 'ubuntu' user (running this script) will own WSL_WORK_DIR.
# Sub-directories created will also be owned by 'ubuntu'.

# --- General Configuration Options ---
REMOVE_PROCESSED_DIRS=true  # Set to false to keep processed directories in the input location
MAX_OPERATION_TIMEOUT=${MAX_OPERATION_TIMEOUT:-1800}  # 30 minutes timeout for individual operations
CHECK_INTERVAL=${CHECK_INTERVAL:-30}           # Check process status every 30 seconds
PIPELINE_EXEC_USER="ubuntu" # Sub-commands (na-pipeline.sh) will be run as this user.
                            # This script itself is expected to be run as 'ubuntu'.

# --- Function to run command with timeout ---
run_with_timeout() {
    local cmd_string="$1"  # The command string to execute
    local timeout_seconds="$2"
    local operation_name="$3"
    local target_user="$4" # The user to run the command as

    local start_ts
    start_ts=$(date +%s)
    local exec_cmd_array=()

    # Determine how to execute the command based on target_user
    if [ -z "$target_user" ] || [ "$(whoami)" == "$target_user" ]; then
        echo "INFO: Operation '$operation_name' will run as current user ('$(whoami)')." >> "$LOG_FILE"
        exec_cmd_array=(bash -c "$cmd_string")
    else
        echo "INFO: Operation '$operation_name' will attempt to run as user '$target_user' via sudo." >> "$LOG_FILE"
        # -n for non-interactive sudo; fails if password needed.
        # -- preserves arguments after it, ensuring $0 and command string are passed correctly.
        exec_cmd_array=(sudo -n -u "$target_user" -- bash -c "$cmd_string")
    fi

    # Execute the command in the background.
    # Pass $0 (this script's name) to the new bash -c shell as its own $0.
    # The $cmd_string is then executed by that bash -c.
    "${exec_cmd_array[@]}" "$0" &
    local cmd_pid=$!

    echo "INFO: Monitoring PID $cmd_pid for operation '$operation_name' (Target User: ${target_user:-current}, Actual User: $(whoami))" >> "$LOG_FILE"

    # Monitoring loop
    while kill -0 "$cmd_pid" 2>/dev/null; do
        local current_ts=$(date +%s)
        local elapsed_seconds=$((current_ts - start_ts))

        if [ "$elapsed_seconds" -gt "$timeout_seconds" ]; then
            echo "ERROR: Operation '$operation_name' (PID $cmd_pid) timed out after ${timeout_seconds} seconds." | tee -a "$LOG_FILE" "$ERROR_LOG"
            # Attempt to kill the process group (PGID) first, then the PID if PGID kill fails or isn't applicable.
            # This helps terminate child processes spawned by the command.
            echo "INFO: Timeout reached. Sending TERM signal to process group of PID $cmd_pid for '$operation_name'." >> "$LOG_FILE"
            kill -TERM -- "-$cmd_pid" 2>/dev/null || kill -TERM "$cmd_pid" 2>/dev/null
            sleep 5 # Grace period

            if kill -0 "$cmd_pid" 2>/dev/null; then # Check if still alive
                echo "INFO: Process $cmd_pid still alive. Sending INT signal to process group for '$operation_name'." >> "$LOG_FILE"
                kill -INT -- "-$cmd_pid" 2>/dev/null || kill -INT "$cmd_pid" 2>/dev/null
                sleep 5
            fi

            if kill -0 "$cmd_pid" 2>/dev/null; then # Check again
                echo "WARNING: Process $cmd_pid still alive. Force killing with SIGKILL for '$operation_name'." | tee -a "$LOG_FILE" "$ERROR_LOG"
                kill -KILL -- "-$cmd_pid" 2>/dev/null || kill -KILL "$cmd_pid" 2>/dev/null
                echo "INFO: Force killed operation '$operation_name' (PID $cmd_pid)." >> "$ERROR_LOG"
            else
                echo "INFO: PID $cmd_pid for '$operation_name' terminated successfully after signal." >> "$LOG_FILE"
            fi
            return 1 # Timeout error
        fi
        
        # CPU usage check (optional, can be noisy)
        local cpu_usage_raw
        cpu_usage_raw=$(ps -p "$cmd_pid" -o %cpu --no-headers 2>/dev/null || echo "") # Handle ps error if PID vanishes
        if [ -n "$cpu_usage_raw" ]; then
            local cpu_usage=$(echo "$cpu_usage_raw" | tr -d ' ')
            # Log only if CPU usage is very low, as it might indicate a stuck process not doing I/O either.
            if [[ "$cpu_usage" == "0.0" || "$cpu_usage" == "0" ]]; then
                echo "DEBUG: Monitored PID $cmd_pid ('$operation_name') shows CPU usage: $cpu_usage%" >> "$LOG_FILE"
            fi
        # else
            # PID might have finished between kill -0 and ps
            # echo "DEBUG: ps command could not retrieve CPU for PID $cmd_pid (likely finished): '$operation_name'" >> "$LOG_FILE"
        fi
        sleep "$CHECK_INTERVAL"
    done
    
    # Wait for the command to finish and get its exit status
    local exit_status=0
    if ! wait "$cmd_pid"; then
        exit_status=$? # Capture exit status if wait itself fails or command returns non-zero
        echo "ERROR: Operation '$operation_name' (PID $cmd_pid, Target User: ${target_user:-current}) failed with exit status $exit_status." | tee -a "$LOG_FILE" "$ERROR_LOG"
    else
        exit_status=$? # Capture exit status if wait succeeds (command might still be non-zero)
        if [ $exit_status -eq 0 ]; then
            echo "INFO: Operation '$operation_name' (PID $cmd_pid, Target User: ${target_user:-current}) completed successfully." >> "$LOG_FILE"
        else
            # This case handles if wait itself didn't error, but the command returned non-zero.
            echo "ERROR: Operation '$operation_name' (PID $cmd_pid, Target User: ${target_user:-current}) finished with non-zero exit status $exit_status." | tee -a "$LOG_FILE" "$ERROR_LOG"
        fi
    fi
    return $exit_status
}

# --- Lock File Management ---
LOCK_FILE_DIR="/tmp" # Using /tmp within the container for the lock file
LOCK_FILE="${LOCK_FILE_DIR}/workspace_na_pipeline.lock"
LOCK_TIMEOUT=300 # 5 minutes for stale lock check

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE")
        if ! [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
            echo "WARNING: Found invalid content ('$lock_pid') in lock file, removing..." | tee -a "$LOG_FILE" "$ERROR_LOG"
            rm -f "$LOCK_FILE"
            return 1 # Lock invalid, can proceed
        fi
        if ! kill -0 "$lock_pid" 2>/dev/null; then
            echo "INFO: Found stale lock file (PID $lock_pid not running), removing..." | tee -a "$LOG_FILE"
            rm -f "$LOCK_FILE"
            return 1 # Stale lock, can proceed
        fi
        
        # Check lock file age only if PID is running
        local lock_file_stat_time lock_time_seconds current_time_seconds
        # Ensure stat command is available and handle potential errors
        lock_file_stat_time=$(stat -c %Y "$LOCK_FILE" 2>/dev/null)
        if [ -z "$lock_file_stat_time" ]; then
            echo "WARNING: Could not stat lock file '$LOCK_FILE' to check age. Assuming lock is problematic and removing." | tee -a "$LOG_FILE" "$ERROR_LOG"
            rm -f "$LOCK_FILE"
            return 1
        fi
        lock_time_seconds=$lock_file_stat_time
        current_time_seconds=$(date +%s)

        if [ $((current_time_seconds - lock_time_seconds)) -gt $LOCK_TIMEOUT ]; then
            echo "WARNING: Lock file is older than $LOCK_TIMEOUT seconds (PID $lock_pid still running but lock is old). Forcing removal..." | tee -a "$LOG_FILE" "$ERROR_LOG"
            rm -f "$LOCK_FILE"
            return 1 # Old lock, proceed with caution
        fi
        return 0 # Lock is active and valid
    fi
    return 1 # No lock file, can proceed
}

if check_lock; then
    echo "ERROR: Another instance of the script is already running (PID $(cat "$LOCK_FILE")). Lock file: $LOCK_FILE" | tee -a "$LOG_FILE" "$ERROR_LOG"
    exit 1
fi
# Create lock file with current script's PID
echo "$CURRENT_SCRIPT_PID" > "$LOCK_FILE"
echo "INFO: Lock file created: $LOCK_FILE with PID $CURRENT_SCRIPT_PID" >> "$LOG_FILE"

# --- Cleanup Functions ---
cleanup_lock() {
    echo "INFO: Cleaning up lock file..." >> "$LOG_FILE"
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid_content
        lock_pid_content=$(cat "$LOCK_FILE")
        if [ "$lock_pid_content" -eq "$CURRENT_SCRIPT_PID" ]; then # Only remove if it's our PID
            rm -f "$LOCK_FILE"
            echo "INFO: Lock file '$LOCK_FILE' cleaned up." >> "$LOG_FILE"
        else
            echo "WARNING: Lock file '$LOCK_FILE' was for a different PID ($lock_pid_content), not removing." | tee -a "$LOG_FILE" "$ERROR_LOG"
        fi
    else
        echo "INFO: Lock file '$LOCK_FILE' already removed or was not created by this instance." >> "$LOG_FILE"
    fi
}

cleanup_temp_workspace() {
    echo "INFO: Cleaning up temporary workspace: ${WSL_WORK_DIR}" >> "$LOG_FILE"
    if [ -d "$WSL_WORK_DIR" ]; then
        # Safety check: ensure WSL_WORK_DIR is not something trivial like /tmp or /
        if [[ "$WSL_WORK_DIR" == "${PROCESSING_BASE_INSIDE_WRAPPER}/pipeline_run_"* ]]; then
            rm -rf "$WSL_WORK_DIR"
            echo "INFO: Temporary workspace '$WSL_WORK_DIR' cleaned up." >> "$LOG_FILE"
        else
            echo "ERROR: WSL_WORK_DIR ('$WSL_WORK_DIR') is not the expected path structure. Aborting cleanup for safety." | tee -a "$LOG_FILE" "$ERROR_LOG"
        fi
    else
        echo "INFO: Temporary workspace '$WSL_WORK_DIR' not found or already cleaned up." >> "$LOG_FILE"
    fi
}

# Trap for cleanup on exit signals
trap 'echo "INFO: Exit trap triggered for PID $CURRENT_SCRIPT_PID. Cleaning up..." >> "$LOG_FILE"; cleanup_temp_workspace; cleanup_lock; echo "INFO: Script exiting." >> "$LOG_FILE"; exit' INT TERM EXIT

# --- Input and Output Directory Handling ---
INPUT_DIR_PARAM="$1"
OUTPUT_DIR_PARAM="$2"

if [ -z "$INPUT_DIR_PARAM" ] || [ -z "$OUTPUT_DIR_PARAM" ]; then
    echo "ERROR: INPUT_DIR and OUTPUT_DIR must be specified as arguments." | tee -a "$LOG_FILE" "$ERROR_LOG"
    echo "Usage: $0 <INPUT_DIR_MOUNT_POINT> <OUTPUT_DIR_MOUNT_POINT>"
    # Trap will handle exit
    exit 1
fi

# These are paths *inside* the container, mapped from host by docker-compose
# Example: /workspace and /destination
echo "INFO: Input directory (inside container): $INPUT_DIR_PARAM" >> "$LOG_FILE"
echo "INFO: Output directory (inside container): $OUTPUT_DIR_PARAM" >> "$LOG_FILE"

if [ ! -d "$INPUT_DIR_PARAM" ]; then
    echo "ERROR: Input directory '$INPUT_DIR_PARAM' (inside container) does not exist or is not accessible." | tee -a "$LOG_FILE" "$ERROR_LOG"
    exit 1
fi
if ! mkdir -p "$OUTPUT_DIR_PARAM" 2>/dev/null; then
    if [ ! -d "$OUTPUT_DIR_PARAM" ] || [ ! -w "$OUTPUT_DIR_PARAM" ]; then
        echo "ERROR: Cannot create or access/write to output directory '$OUTPUT_DIR_PARAM' (inside container)." | tee -a "$LOG_FILE" "$ERROR_LOG"
        exit 1
    fi
fi

# --- Required Script Paths ---
# These scripts are expected to be in the same directory as workspace_na_pipeline.sh or at a known path.
NA_PIPELINE="${SCRIPT_DIR}/na-pipeline.sh"
XML2TEXT="${SCRIPT_DIR}/xml2text.sh"

for script_to_check in "$NA_PIPELINE" "$XML2TEXT"; do
    if [ ! -f "$script_to_check" ]; then
        echo "ERROR: Required script not found: $script_to_check" | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1;
    fi
    if [ ! -x "$script_to_check" ]; then
        echo "ERROR: Required script not executable: $script_to_check. Please chmod +x it." | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1;
    fi
done
echo "INFO: Using na-pipeline.sh from: ${NA_PIPELINE}" >> "$LOG_FILE"
echo "INFO: Using xml2text.sh from: ${XML2TEXT}" >> "$LOG_FILE"


# --- Helper Functions ---
needs_processing() {
    local source_file_path="$1"
    local target_output_base_dir="$2"
    local source_filename
    source_filename=$(basename "$source_file_path")
    local file_extension="${source_filename##*.}"
    local name_no_ext="${source_filename%.*}"
    local source_mod_time
    source_mod_time=$(stat -c %Y "$source_file_path")
    
    # Pattern for processed files: name_no_ext_DATE.extension
    local processed_file_pattern="${name_no_ext}_*.$file_extension"
    
    # Check if any processed version exists
    # Using find with -quit for efficiency
    if find "$target_output_base_dir" -maxdepth 1 -name "$processed_file_pattern" -print -quit | grep -q .; then
        local newest_destination_mod_time=0
        # Loop through all matching destination files to find the newest
        for dest_file_candidate in "$target_output_base_dir"/"$processed_file_pattern"; do
            if [ -f "$dest_file_candidate" ]; then # Ensure it's a file
                local current_dest_mod_time
                current_dest_mod_time=$(stat -c %Y "$dest_file_candidate")
                if [ "$current_dest_mod_time" -gt "$newest_destination_mod_time" ]; then
                    newest_destination_mod_time=$current_dest_mod_time
                fi
            fi
        done
        
        if [ "$source_mod_time" -gt "$newest_destination_mod_time" ]; then
            echo "INFO: Source file '$source_filename' is newer than existing processed files. Processing required." >> "$LOG_FILE"
            return 0 # Needs processing
        else
            echo "INFO: File '$source_filename' already processed and source is not newer." >> "$LOG_FILE"
            return 1 # Does not need processing
        fi
    fi
    echo "INFO: No processed version of '$source_filename' found in '$target_output_base_dir'. Processing required." >> "$LOG_FILE"
    return 0 # Needs processing
}

copy_with_date_suffix() {
    local source_file_to_copy="$1"
    local destination_base_dir="$2"
    local original_filename
    original_filename=$(basename "$source_file_to_copy")
    local file_ext="${original_filename##*.}"
    local name_part="${original_filename%.*}"
    local date_suffix
    date_suffix=$(date +"%d%m%Y") # DDMMYYYY format
    local new_target_filename="${name_part}_${date_suffix}.${file_ext}"
    
    mkdir -p "${destination_base_dir}" # Ensure destination directory exists
    echo "INFO: Copying from '${source_file_to_copy}' to '${destination_base_dir}/${new_target_filename}'" >> "$LOG_FILE"
    if ! cp -p "${source_file_to_copy}" "${destination_base_dir}/${new_target_filename}"; then # -p preserves mode, ownership, timestamps
        echo "ERROR: Failed to copy '${source_file_to_copy}' to '${destination_base_dir}/${new_target_filename}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
        return 1
    fi
    echo "INFO: Successfully copied '${source_file_to_copy}' to '${destination_base_dir}/${new_target_filename}'" >> "$LOG_FILE"
    return 0
}

# --- Main Processing Logic ---
echo "--- Initial Directory Scan ---" | tee -a "$LOG_FILE"
echo "INFO: Tree of the input directory ($INPUT_DIR_PARAM):" | tee -a "$LOG_FILE"
tree "$INPUT_DIR_PARAM" >> "$LOG_FILE" 2>&1 || echo "WARNING: 'tree' command not found or failed on $INPUT_DIR_PARAM. Skipping tree view." | tee -a "$LOG_FILE" "$ERROR_LOG"
echo "INFO: Tree of the output directory ($OUTPUT_DIR_PARAM):" | tee -a "$LOG_FILE"
tree "$OUTPUT_DIR_PARAM" >> "$LOG_FILE" 2>&1 || echo "WARNING: 'tree' command not found or failed on $OUTPUT_DIR_PARAM. Skipping tree view." | tee -a "$LOG_FILE" "$ERROR_LOG"

# Iterate over subdirectories in the input directory
# Using find for robustness with spaces or special characters in directory names
find "$INPUT_DIR_PARAM" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' current_processing_dir_path; do
    current_dir_name=$(basename "${current_processing_dir_path}")
    echo "" # Newline for readability
    echo "--- Processing directory: ${current_dir_name} ---" | tee -a "$LOG_FILE"
    
    # Define item-specific temporary workspace (e.g., /tmp/pipeline_run_XYZ/HarrieB_Test1)
    item_specific_temp_workspace="${WSL_WORK_DIR}/${current_dir_name}"
    mkdir -p "${item_specific_temp_workspace}"
    # Permissions for item-specific temp workspace.
    # Since 'ubuntu' user owns WSL_WORK_DIR, it will own this too.
    # Sub-processes run as 'ubuntu' should have access.
    # chmod -R 0777 "${item_specific_temp_workspace}" # Can be used if more open permissions are needed for tools
    echo "INFO: Item-specific temporary workspace: ${item_specific_temp_workspace}" >> "$LOG_FILE"
    
    # Create 'page' subdirectory within item-specific temp workspace
    mkdir -p "${item_specific_temp_workspace}/page"
    echo "INFO: Permissions for ${item_specific_temp_workspace}/page: $(ls -ld "${item_specific_temp_workspace}/page")" >> "$LOG_FILE"
    
    echo "INFO: Copying image files from '${current_processing_dir_path}' to '${item_specific_temp_workspace}'" >> "$LOG_FILE"
    # Copy image files (jpg, png, tif) to the item-specific temporary workspace
    find "${current_processing_dir_path}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \) -exec cp -t "${item_specific_temp_workspace}/" {} +
    
    # Define final output subdirectory for this item (e.g., /destination/HarrieB_Test1)
    sanitized_dir_name=$(echo "$current_dir_name" | tr ' ' '_') # Sanitize for directory name
    final_item_output_dir="${OUTPUT_DIR_PARAM}/${sanitized_dir_name}"
    mkdir -p "${final_item_output_dir}"

    # Determine if this directory needs processing
    requires_processing_flag=false
    if [ -d "$current_processing_dir_path" ] && [ -n "$(ls -A "$current_processing_dir_path" 2>/dev/null)" ]; then
        # Check each file in the source item directory
        for file_in_item_source in "${current_processing_dir_path}"/*; do
            if [ -f "$file_in_item_source" ]; then
                if needs_processing "$file_in_item_source" "${final_item_output_dir}"; then
                    requires_processing_flag=true
                    break # Found one file needing processing, so the whole directory does
                fi
            fi
        done
    else
        echo "INFO: Source item directory '${current_processing_dir_path}' is empty or does not exist. Skipping." >> "$LOG_FILE"
    fi
    
    if [ "$requires_processing_flag" = true ]; then
        echo "INFO: Directory '${current_dir_name}' requires processing." | tee -a "$LOG_FILE"
        
        # Define output directory for na-pipeline.sh within the item's temporary workspace
        na_pipeline_temp_output_dir="${item_specific_temp_workspace}/output_from_na_pipeline"
        mkdir -p "${na_pipeline_temp_output_dir}"

        # Execute na-pipeline.sh
        echo "INFO: Executing na-pipeline.sh. Input: '${item_specific_temp_workspace}', Output: '${na_pipeline_temp_output_dir}'" | tee -a "$LOG_FILE"
        if ! run_with_timeout "${NA_PIPELINE} ${item_specific_temp_workspace} ${na_pipeline_temp_output_dir}" "$MAX_OPERATION_TIMEOUT" "na-pipeline.sh for ${current_dir_name}" "$PIPELINE_EXEC_USER"; then
            echo "ERROR: na-pipeline.sh failed for directory ${current_dir_name}. See logs for details." | tee -a "$LOG_FILE" "$ERROR_LOG"
            # Continue to the next directory in the input rather than exiting the whole script
            # The error is already logged by run_with_timeout.
            # The trap will handle cleanup of the main WSL_WORK_DIR if the script exits due to other 'set -e' issues.
            # Item-specific cleanup happens at the end of this loop iteration.
            continue 
        fi

        # Process XML files if 'page' directory was populated by na-pipeline.sh
        page_xml_source_dir="${item_specific_temp_workspace}/page" 
        if [ -d "${page_xml_source_dir}" ] && [ "$(ls -A "${page_xml_source_dir}" 2>/dev/null)" ]; then
            echo "INFO: Converting XML files to text using xml2text.sh from '${page_xml_source_dir}'" | tee -a "$LOG_FILE"
            # Output of xml2text goes to the same na_pipeline_temp_output_dir (or a different one if preferred)
            if ! run_with_timeout "${XML2TEXT} ${page_xml_source_dir} ${na_pipeline_temp_output_dir}" 900 "xml2text.sh for ${current_dir_name}" "$PIPELINE_EXEC_USER"; then
                 echo "ERROR: xml2text.sh failed for ${current_dir_name}. See logs." | tee -a "$LOG_FILE" "$ERROR_LOG"
            else
                 echo "INFO: XML to text conversion completed for ${current_dir_name}." >> "$LOG_FILE"
            fi
        else
            echo "INFO: No 'page' directory with XML files found in '${page_xml_source_dir}' or directory is empty. Skipping XML to text conversion for ${current_dir_name}." >> "$LOG_FILE"
        fi

        # Copy processed files from na_pipeline_temp_output_dir to the final item output directory
        if [ -d "${na_pipeline_temp_output_dir}" ] && [ "$(ls -A "${na_pipeline_temp_output_dir}" 2>/dev/null)" ]; then
            echo "INFO: Copying processed files from '${na_pipeline_temp_output_dir}' to '${final_item_output_dir}'" | tee -a "$LOG_FILE"
            for file_to_copy_from_temp in "${na_pipeline_temp_output_dir}/"*; do
                if [ -f "$file_to_copy_from_temp" ]; then
                    copy_with_date_suffix "$file_to_copy_from_temp" "${final_item_output_dir}"
                fi
            done
            echo "INFO: Copied output to '${final_item_output_dir}' for ${current_dir_name}." >> "$LOG_FILE"
        else
            echo "WARNING: Output directory from na-pipeline ('${na_pipeline_temp_output_dir}') not found or empty for ${current_dir_name} after processing." | tee -a "$LOG_FILE" "$ERROR_LOG"
        fi

        # Remove original source directory if configured and processing was successful
        if [ "$REMOVE_PROCESSED_DIRS" = true ]; then
            echo "INFO: Checking processing in '${final_item_output_dir}' to consider removing source '${current_processing_dir_path}'" >> "$LOG_FILE"
            current_date_for_suffix=$(date +"%d%m%Y")
            # Count files with today's date suffix in the final output for this item
            # Using find to count files matching the pattern *_DATE.EXT
            processed_files_with_date_count=$(find "${final_item_output_dir}" -maxdepth 1 -type f -name "*_${current_date_for_suffix}.*" 2>/dev/null | wc -l)
            
            if [ "$processed_files_with_date_count" -gt 0 ]; then
                echo "INFO: Found ${processed_files_with_date_count} processed files with today's date suffix. Attempting to remove source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                if [ ! -d "${current_processing_dir_path}" ]; then
                    echo "WARNING: Source directory to remove does not exist: '${current_processing_dir_path}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
                elif [ ! "$(ls -A "${current_processing_dir_path}" 2>/dev/null)" ]; then
                    echo "INFO: Source directory '${current_processing_dir_path}' is already empty. Removing..." >> "$LOG_FILE"
                    rm -rf "${current_processing_dir_path}" && echo "INFO: Removed empty source: '${current_processing_dir_path}'" >> "$LOG_FILE" || echo "ERROR: Failed to remove empty source '${current_processing_dir_path}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
                else
                    echo "INFO: Attempting to remove non-empty source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                    if rm -rf "${current_processing_dir_path}"; then
                        echo "INFO: Removed source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                    else
                        echo "ERROR: Failed to remove source directory '${current_processing_dir_path}'. Manual check may be needed." | tee -a "$LOG_FILE" "$ERROR_LOG"
                    fi
                fi
                # Verify removal
                if [ -d "${current_processing_dir_path}" ]; then
                    echo "WARNING: Directory still exists after removal attempt: '${current_processing_dir_path}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
                    ls -la "${current_processing_dir_path}" >> "$ERROR_LOG" # Log details if removal failed
                else
                    echo "INFO: Verified removal of source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                fi
            else
                echo "INFO: Skipping source removal for '${current_processing_dir_path}': No files with today's date suffix (${current_date_for_suffix}) found in '${final_item_output_dir}'." >> "$LOG_FILE"
            fi
        else
            echo "INFO: Directory removal disabled (REMOVE_PROCESSED_DIRS=false) for '${current_processing_dir_path}'." >> "$LOG_FILE"
        fi
    else
        echo "INFO: Skipping directory ${current_dir_name} as all files are already processed/up to date or source is empty." | tee -a "$LOG_FILE"
    fi
    
    # Clean up item-specific temporary workspace
    echo "INFO: Cleaning up item-specific temporary workspace: ${item_specific_temp_workspace}" >> "$LOG_FILE"
    if [[ "$item_specific_temp_workspace" == "${WSL_WORK_DIR}/${current_dir_name}" ]] && [ -n "${current_dir_name}" ] && [ -d "${item_specific_temp_workspace}" ]; then
        rm -rf "${item_specific_temp_workspace}"
        echo "INFO: Cleaned up ${item_specific_temp_workspace}" >> "$LOG_FILE"
    else
        echo "ERROR: Item-specific workspace path unsafe ('${item_specific_temp_workspace}') or does not exist. Not removing." | tee -a "$LOG_FILE" "$ERROR_LOG"
    fi
    echo "--- Finished processing directory: ${current_dir_name} ---" | tee -a "$LOG_FILE"
done

echo "" # Newline for readability
echo "--- Pipeline Processing Completed: $(date) ---" | tee -a "$LOG_FILE"
# Final cleanup (WSL_WORK_DIR and lock file) will be handled by the EXIT trap.
