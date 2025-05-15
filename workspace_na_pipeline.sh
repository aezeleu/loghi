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

# Create temporary workspace - define this BEFORE it's used in mkdir commands
WSL_WORK_DIR="/tmp/workspace_na_pipeline"

# Configuration options
REMOVE_PROCESSED_DIRS=true  # Set to false to keep processed directories in the input location
MAX_OPERATION_TIMEOUT=1800  # 30 minutes timeout for individual operations
CHECK_INTERVAL=30           # Check every 30 seconds

# Ensure all needed directories exist
mkdir -p "${WSL_WORK_DIR}"
mkdir -p "${LOG_DIR}"

chmod -R 777 /tmp

# Function to run command with timeout
run_with_timeout() {
    local cmd="$1"
    local timeout="$2"
    local operation="$3"
    local start_time=$(date +%s)
    
    $cmd &
    local cmd_pid=$!
    
    while kill -0 "$cmd_pid" 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt "$timeout" ]; then
            echo "Error: Operation '$operation' timed out after ${timeout} seconds" >> "$ERROR_LOG"
            kill -TERM "$cmd_pid" 2>/dev/null; sleep 5
            if kill -0 "$cmd_pid" 2>/dev/null; then kill -INT "$cmd_pid" 2>/dev/null; sleep 5; fi
            if kill -0 "$cmd_pid" 2>/dev/null; then kill -9 "$cmd_pid" 2>/dev/null; echo "Force killed operation '$operation'" >> "$ERROR_LOG"; fi
            return 1
        fi
        
        local cpu_usage_raw=$(ps -p "$cmd_pid" -o %cpu --no-headers)
        local cpu_usage=$(echo "$cpu_usage_raw" | tr -d ' ') 
        if [[ "$cpu_usage" == "0.0" || "$cpu_usage" == "0" ]]; then
            echo "Warning: Operation '$operation' (PID $cmd_pid) is not using CPU (usage: $cpu_usage)" >> "$ERROR_LOG"
        fi
        sleep $CHECK_INTERVAL
    done
    wait $cmd_pid
    return $?
}

LOCK_FILE="/tmp/workspace_na_pipeline.lock"
LOCK_TIMEOUT=300

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid; lock_pid=$(cat "$LOCK_FILE")
        if ! [[ "$lock_pid" =~ ^[0-9]+$ ]]; then echo "Found invalid content in lock file, removing..."; rm -f "$LOCK_FILE"; return 1; fi
        if ! kill -0 "$lock_pid" 2>/dev/null; then echo "Found stale lock file (PID $lock_pid not running), removing..."; rm -f "$LOCK_FILE"; return 1; fi
        local lock_time; lock_time=$(stat -c %Y "$LOCK_FILE"); local current_time; current_time=$(date +%s)
        if [ $((current_time - lock_time)) -gt $LOCK_TIMEOUT ]; then echo "Lock file is older than $LOCK_TIMEOUT seconds (PID $lock_pid still running but lock is old), removing..."; rm -f "$LOCK_FILE"; return 1; fi
        return 0
    fi
    return 1
}

if check_lock; then echo "Error: Another instance of the script is already running (PID $(cat "$LOCK_FILE"))."; echo "Lock file exists at: $LOCK_FILE"; exit 1; fi
echo $$ > "$LOCK_FILE"

cleanup_lock() {
    echo "Cleaning up lock file..."; local lock_pid_content
    if [ -f "$LOCK_FILE" ]; then lock_pid_content=$(cat "$LOCK_FILE"); if [ "$lock_pid_content" -eq "$$" ]; then rm -f "$LOCK_FILE"; echo "Lock file cleaned up."; else echo "Lock file was for a different PID ($lock_pid_content), not removing."; fi
    else echo "Lock file already removed."; fi
}
cleanup_temp_workspace() {
    echo "Cleaning up temporary workspace..."
    if [ -d "$WSL_WORK_DIR" ]; then if [[ "$WSL_WORK_DIR" == "/tmp/workspace_na_pipeline" ]]; then rm -rf "$WSL_WORK_DIR"; echo "Temporary workspace '$WSL_WORK_DIR' cleaned up."; else echo "Error: WSL_WORK_DIR is not the expected path ('$WSL_WORK_DIR'), aborting cleanup for safety." >> "$ERROR_LOG"; fi
    else echo "Temporary workspace '$WSL_WORK_DIR' not found."; fi
}
trap 'cleanup_temp_workspace; cleanup_lock; echo "Script exiting."; exit' INT TERM EXIT

INPUT_DIR="$1"; OUTPUT_DIR="$2"
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then echo "Error: INPUT_DIR and OUTPUT_DIR must be specified."; echo "Usage: $0 <INPUT_DIR> <OUTPUT_DIR>"; exit 1; fi
if [ ! -d "$INPUT_DIR" ]; then echo "Error: Input directory '$INPUT_DIR' does not exist or is not accessible."; exit 1; fi
if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then echo "Error: Cannot create or access output directory '$OUTPUT_DIR'."; exit 1; fi
mkdir -p "$OUTPUT_DIR"; mkdir -p "${WSL_WORK_DIR}"
NA_PIPELINE="${SCRIPT_DIR}/na-pipeline.sh"; XML2TEXT="${SCRIPT_DIR}/xml2text.sh"
for script_path in "$NA_PIPELINE" "$XML2TEXT"; do if [ ! -f "$script_path" ]; then echo "Error: Required script not found: $script_path"; exit 1; fi; if [ ! -x "$script_path" ]; then echo "Error: Required script not executable: $script_path"; exit 1; fi; done

needs_processing() {
    local source_file="$1"; local target_output_dir="$2"; local filename; filename=$(basename "$source_file"); local extension; extension="${filename##*.}"; local name_without_ext; name_without_ext="${filename%.*}"; local source_mtime; source_mtime=$(stat -c %Y "$source_file"); local existing_processed_files; existing_processed_files=$(find "$target_output_dir" -maxdepth 1 -name "${name_without_ext}_*.$extension" -print -quit)
    if [ -n "$existing_processed_files" ]; then
        local newest_dest_mtime=0; local dest_file; for dest_file in "$target_output_dir"/${name_without_ext}_*.$extension; do if [ -f "$dest_file" ]; then local current_dest_mtime; current_dest_mtime=$(stat -c %Y "$dest_file"); if [ "$current_dest_mtime" -gt "$newest_dest_mtime" ]; then newest_dest_mtime=$current_dest_mtime; fi; fi; done
        if [ "$source_mtime" -gt "$newest_dest_mtime" ]; then echo "Source file '$filename' is newer. Processing required."; return 0; else echo "File '$filename' already processed and source not newer."; return 1; fi
    fi
    echo "No processed version of '$filename' found. Processing required."; return 0
}
copy_with_date_suffix() {
    local source_file="$1"; local dest_dir="$2"; local filename; filename=$(basename "$source_file"); local extension; extension="${filename##*.}"; local name_without_ext; name_without_ext="${filename%.*}"; local current_date; current_date=$(date +"%d%m%Y"); local new_filename; new_filename="${name_without_ext}_${current_date}.${extension}"; mkdir -p "${dest_dir}"
    echo "Copying from ${source_file} to ${dest_dir}/${new_filename}"; if ! cp -p "${source_file}" "${dest_dir}/${new_filename}"; then echo "Error: Failed to copy ${source_file} to ${dest_dir}/${new_filename}" >> "$ERROR_LOG"; return 1; fi
    echo "Successfully copied ${source_file} to ${dest_dir}/${new_filename}"; return 0
}

echo 'Tree of the workspace directory (INPUT_DIR):'; tree "$INPUT_DIR" || echo "tree command not found or failed on $INPUT_DIR"
echo 'Tree of the destination directory (OUTPUT_DIR):'; tree "$OUTPUT_DIR" || echo "tree command not found or failed on $OUTPUT_DIR"

for dir_path in "${INPUT_DIR}"/*/ ; do
    if [ ! -d "${dir_path}" ]; then echo "Skipping non-directory item: ${dir_path}"; continue; fi
    dir_name=$(basename "${dir_path}"); echo "--- Processing directory: ${dir_name} ---"
    workspace_dir="${WSL_WORK_DIR}/${dir_name}"; mkdir -p "${workspace_dir}"
    
    echo "Setting 777 permissions recursively for temporary workspace: ${workspace_dir}"
    chmod -R 777 "${workspace_dir}"
    echo "Permissions for ${workspace_dir} (loghi-wrapper perspective):"; ls -ld "${workspace_dir}"
    
    mkdir -p "${workspace_dir}/page" 
    chmod 777 "${workspace_dir}/page" # Explicitly set page dir perms
    echo "Permissions for ${workspace_dir}/page (loghi-wrapper perspective):"; ls -ld "${workspace_dir}/page"
    
    echo "Copying image files from ${dir_path} to ${workspace_dir}"
    find "${dir_path}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \) -exec cp -t "${workspace_dir}/" {} +
    
    safe_subdir_name=$(echo "$dir_name" | tr ' ' '_'); final_output_subdir="${OUTPUT_DIR}/${safe_subdir_name}"; mkdir -p "${final_output_subdir}"
    process_this_directory=false
    for file_in_source in "${dir_path}"/*; do if [ -f "$file_in_source" ]; then if needs_processing "$file_in_source" "${final_output_subdir}"; then process_this_directory=true; break; fi; fi; done
    
    if [ "$process_this_directory" = true ]; then
        echo "Directory '${dir_name}' requires processing."
        na_pipeline_output_dir="${workspace_dir}/output"; mkdir -p "${na_pipeline_output_dir}" 

        echo "Executing na-pipeline.sh. Input: ${workspace_dir}, Output: ${na_pipeline_output_dir}"
        if ! run_with_timeout "${NA_PIPELINE} ${workspace_dir} ${na_pipeline_output_dir}" "$MAX_OPERATION_TIMEOUT" "na-pipeline.sh for ${dir_name}"; then
            echo "Error: na-pipeline.sh failed for directory ${dir_name}" >> "$ERROR_LOG"; continue 
        fi

        page_xml_dir="${workspace_dir}/page" 
        if [ -d "${page_xml_dir}" ] && [ "$(ls -A "${page_xml_dir}")" ]; then
            echo "Converting XML files to text using xml2text.sh from ${page_xml_dir}"
            if ! run_with_timeout "${XML2TEXT} ${page_xml_dir} ${na_pipeline_output_dir}" 900 "xml2text.sh for ${dir_name}"; then echo "Error: xml2text.sh failed for ${dir_name}" >> "$ERROR_LOG"; else echo "XML to text conversion completed for ${dir_name}"; fi
        else echo "Note: No 'page' directory with XML files found in ${page_xml_dir} - skipping XML conversion for ${dir_name}"; fi

        if [ -d "${na_pipeline_output_dir}" ] && [ "$(ls -A "${na_pipeline_output_dir}")" ]; then
            echo "Copying processed files from ${na_pipeline_output_dir} to ${final_output_subdir}"
            for file_to_copy in "${na_pipeline_output_dir}/"*; do if [ -f "$file_to_copy" ]; then copy_with_date_suffix "$file_to_copy" "${final_output_subdir}"; fi; done
            echo "Copied output to ${final_output_subdir} for ${dir_name}"
        else echo "Warning: Output directory ${na_pipeline_output_dir} not found or empty for ${dir_name}" >> "$ERROR_LOG"; fi

        if [ "$REMOVE_PROCESSED_DIRS" = true ]; then
            echo "Checking processing in ${final_output_subdir} to consider removing source ${dir_path}"; current_date_suffix=$(date +"%d%m%Y"); processed_files_count=$(find "${final_output_subdir}" -maxdepth 1 -type f -name "*_${current_date_suffix}.*" | wc -l)
            if [ "$processed_files_count" -gt 0 ]; then
                echo "Found ${processed_files_count} processed files. Attempting to remove source: ${dir_path}"
                if [ ! -d "${dir_path}" ]; then echo "Warning: Source dir to remove does not exist: ${dir_path}" >> "$ERROR_LOG"
                elif [ ! "$(ls -A "${dir_path}")" ]; then echo "Source dir ${dir_path} is already empty. Removing..."; rm -rf "${dir_path}" && echo "Removed empty source: ${dir_path}" || echo "Failed to remove empty source ${dir_path}" >> "$ERROR_LOG"
                else
                    echo "Attempting to remove non-empty source: ${dir_path}"; if rm -rf "${dir_path}"; then echo "Removed source: ${dir_path}"
                    else echo "Direct removal of '${dir_path}' failed. Trying WSL path..." >> "$ERROR_LOG"; windows_path_original_logic=$(echo "${dir_path}" | sed 's/\/mnt\//\/mnt\/i\//'); echo "Attempting removal with: ${windows_path_original_logic}"
                        if rm -rf "${windows_path_original_logic}"; then echo "Removed with WSL path: ${windows_path_original_logic}"; else echo "Warning: Failed to remove ${dir_path} with both methods." >> "$ERROR_LOG"; fi
                    fi
                fi
                if [ -d "${dir_path}" ]; then echo "Warning: Dir still exists: ${dir_path}" >> "$ERROR_LOG"; ls -la "${dir_path}" >> "$ERROR_LOG"; else echo "Verified removal of: ${dir_path}"; fi
            else echo "Skipping source removal for ${dir_path}: No files with today's date suffix in ${final_output_subdir}"; fi
        else echo "Directory removal disabled for ${dir_path}"; fi
    else echo "Skipping directory ${dir_name} as all files are already processed/up to date."; fi
    
    echo "Cleaning up item-specific temporary workspace: ${workspace_dir}"
    if [[ "$workspace_dir" == "${WSL_WORK_DIR}/${dir_name}" ]] && [ -n "${dir_name}" ]; then rm -rf "${workspace_dir}"; echo "Cleaned up ${workspace_dir}"; else echo "Error: Item-specific workspace path unsafe ('${workspace_dir}'), not removing." >> "$ERROR_LOG"; fi
    echo "--- Finished processing directory: ${dir_name} ---"
done
echo "Processing completed."