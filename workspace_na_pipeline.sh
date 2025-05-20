#!/bin/bash

# Ensure script fails on any error
set -e

# --- Script Setup & Configuration ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Script directory: $SCRIPT_DIR"
cd "$SCRIPT_DIR"
echo "Changed working directory to: $(pwd)"

# --- Environment Variable Configuration ---
PIPELINE_ENABLE_DEBUG_LOGGING="${PIPELINE_ENABLE_DEBUG_LOGGING:-false}" 
PIPELINE_KEEP_TEMP_RUN_DIR="${PIPELINE_KEEP_TEMP_RUN_DIR:-false}"     

# Function to list directory contents for debugging
list_dir_contents_workspace() {
    if [ "$PIPELINE_ENABLE_DEBUG_LOGGING" != "true" ]; then
        return 0
    fi
    local dir_path="$1"
    local description="$2"
    echo "DEBUG_LOG (workspace_na_pipeline.sh): Listing contents of ${description} ('${dir_path}'):"
    if [ -d "$dir_path" ]; then
        find "$dir_path" -ls || echo "DEBUG_LOG (workspace_na_pipeline.sh): Failed to list '${dir_path}' or directory is empty (using find)."
    else
        echo "DEBUG_LOG (workspace_na_pipeline.sh): Directory '${dir_path}' does not exist for listing."
    fi
    echo "--- End of listing for ${description} ---"
}


PROCESSING_BASE_INSIDE_WRAPPER="/tmp" 
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
CURRENT_SCRIPT_PID=$$ 
WSL_WORK_DIR="${PROCESSING_BASE_INSIDE_WRAPPER}/pipeline_run_${TIMESTAMP}_${CURRENT_SCRIPT_PID}"
LOG_DIR_BASE="/app/logs" 
LOG_DIR="${LOG_DIR_BASE}/run_${TIMESTAMP}_${CURRENT_SCRIPT_PID}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/pipeline.log"
ERROR_LOG="${LOG_DIR}/pipeline_errors.log"

echo "--- Pipeline Execution Start: $(date) ---" | tee -a "$LOG_FILE"
echo "INFO: Running in Docker-in-Docker (DinD) mode." | tee -a "$LOG_FILE"
echo "INFO: Pipeline temporary workspace (WSL_WORK_DIR): ${WSL_WORK_DIR}" | tee -a "$LOG_FILE"
echo "INFO: Logging to: ${LOG_FILE} and ${ERROR_LOG}" | tee -a "$LOG_FILE"
echo "INFO: Current user: $(whoami) (UID: $(id -u), GID: $(id -g))" | tee -a "$LOG_FILE"
echo "INFO: Docker CLI version (talking to internal daemon): $(docker --version 2>/dev/null || echo 'docker CLI not found or error')" | tee -a "$LOG_FILE"
echo "INFO: PIPELINE_ENABLE_DEBUG_LOGGING set to: ${PIPELINE_ENABLE_DEBUG_LOGGING}" | tee -a "$LOG_FILE"
echo "INFO: PIPELINE_KEEP_TEMP_RUN_DIR set to: ${PIPELINE_KEEP_TEMP_RUN_DIR}" | tee -a "$LOG_FILE"


mkdir -p "${WSL_WORK_DIR}"

REMOVE_PROCESSED_DIRS="${REMOVE_PROCESSED_DIRS:-true}"
MAX_OPERATION_TIMEOUT=${MAX_OPERATION_TIMEOUT:-1800} 
CHECK_INTERVAL=${CHECK_INTERVAL:-30}      
PIPELINE_EXEC_USER="ubuntu" 

COPY_SOURCE_IMAGES_ENABLED="${COPY_SOURCE_IMAGES:-true}"
COPY_BASELINE_IMAGES_ENABLED="${COPY_BASELINE_IMAGES:-true}"
echo "INFO: Configuration - COPY_SOURCE_IMAGES_ENABLED: ${COPY_SOURCE_IMAGES_ENABLED}" | tee -a "$LOG_FILE"
echo "INFO: Configuration - COPY_BASELINE_IMAGES_ENABLED: ${COPY_BASELINE_IMAGES_ENABLED}" | tee -a "$LOG_FILE"

run_with_timeout() {
    local cmd_string="$1" 
    local timeout_seconds="$2"
    local operation_name="$3"
    local target_user="$4" 
    local start_ts exec_cmd_array cmd_pid current_ts elapsed_seconds actual_exit_status

    start_ts=$(date +%s)
    exec_cmd_array=()

    if [ -z "$target_user" ] || [ "$(whoami)" == "$target_user" ]; then
        echo "INFO (run_with_timeout): Operation '$operation_name' will run as current user ('$(whoami)')." >> "$LOG_FILE"
        exec_cmd_array=(bash -c "$cmd_string")
    else
        echo "INFO (run_with_timeout): Operation '$operation_name' will attempt to run as user '$target_user' via sudo." >> "$LOG_FILE"
        exec_cmd_array=(sudo -n -u "$target_user" -- bash -c "$cmd_string")
    fi

    # Execute the command in the background
    # The subshell's $0 will be the name of this script.
    "${exec_cmd_array[@]}" "$0" & 
    cmd_pid=$!
    echo "INFO (run_with_timeout): Monitoring PID $cmd_pid for operation '$operation_name' (Target User: ${target_user:-current})" >> "$LOG_FILE"

    # Monitoring loop
    while kill -0 "$cmd_pid" 2>/dev/null; do
        current_ts=$(date +%s)
        elapsed_seconds=$((current_ts - start_ts))
        if [ "$elapsed_seconds" -gt "$timeout_seconds" ]; then
            echo "ERROR (run_with_timeout): Operation '$operation_name' (PID $cmd_pid) timed out after ${timeout_seconds} seconds." | tee -a "$LOG_FILE" "$ERROR_LOG"
            kill -TERM -- "-$cmd_pid" 2>/dev/null || kill -TERM "$cmd_pid" 2>/dev/null
            sleep 5 
            if kill -0 "$cmd_pid" 2>/dev/null; then 
                kill -INT -- "-$cmd_pid" 2>/dev/null || kill -INT "$cmd_pid" 2>/dev/null; sleep 5;
            fi
            if kill -0 "$cmd_pid" 2>/dev/null; then 
                kill -KILL -- "-$cmd_pid" 2>/dev/null || kill -KILL "$cmd_pid" 2>/dev/null;
                echo "INFO (run_with_timeout): Force killed operation '$operation_name' (PID $cmd_pid)." >> "$ERROR_LOG"
            else
                echo "INFO (run_with_timeout): PID $cmd_pid for '$operation_name' terminated successfully after signal." >> "$LOG_FILE"
            fi
            return 1 # Timeout error
        fi
        sleep "$CHECK_INTERVAL"
    done
    
    # Wait for the command to finish and get its actual exit status
    wait "$cmd_pid"
    actual_exit_status=$? # Capture the exit status of the command executed by bash -c
    
    if [ $actual_exit_status -eq 0 ]; then
        echo "INFO (run_with_timeout): Operation '$operation_name' (PID $cmd_pid) completed successfully (Exit Status: 0)." >> "$LOG_FILE"
    else
        echo "ERROR (run_with_timeout): Operation '$operation_name' (PID $cmd_pid) failed or finished with non-zero (Exit Status: $actual_exit_status)." | tee -a "$LOG_FILE" "$ERROR_LOG"
    fi
    return $actual_exit_status
}

LOCK_FILE_DIR="/tmp" 
LOCK_FILE="${LOCK_FILE_DIR}/workspace_na_pipeline.lock"
LOCK_TIMEOUT=300 

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid lock_file_stat_time lock_time_seconds current_time_seconds
        lock_pid=$(cat "$LOCK_FILE")
        if ! [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
            echo "WARNING: Invalid PID ('$lock_pid') in lock file. Removing." | tee -a "$LOG_FILE" "$ERROR_LOG"; rm -f "$LOCK_FILE"; return 1;
        fi
        if ! kill -0 "$lock_pid" 2>/dev/null; then
            echo "INFO: Stale lock file (PID $lock_pid not running). Removing." | tee -a "$LOG_FILE"; rm -f "$LOCK_FILE"; return 1;
        fi
        lock_file_stat_time=$(stat -c %Y "$LOCK_FILE" 2>/dev/null)
        if [ -z "$lock_file_stat_time" ]; then
            echo "WARNING: Could not stat lock file '$LOCK_FILE'. Removing." | tee -a "$LOG_FILE" "$ERROR_LOG"; rm -f "$LOCK_FILE"; return 1;
        fi
        lock_time_seconds=$lock_file_stat_time
        current_time_seconds=$(date +%s)
        if [ $((current_time_seconds - lock_time_seconds)) -gt $LOCK_TIMEOUT ]; then
            echo "WARNING: Lock file older than $LOCK_TIMEOUTs (PID $lock_pid running). Forcing removal." | tee -a "$LOG_FILE" "$ERROR_LOG"; rm -f "$LOCK_FILE"; return 1;
        fi
        return 0 
    fi
    return 1 
}

if check_lock; then
    echo "ERROR: Another instance running (PID $(cat "$LOCK_FILE")). Lock file: $LOCK_FILE" | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1;
fi
echo "$CURRENT_SCRIPT_PID" > "$LOCK_FILE"
echo "INFO: Lock file created: $LOCK_FILE with PID $CURRENT_SCRIPT_PID" >> "$LOG_FILE"

cleanup_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid_content=$(cat "$LOCK_FILE")
        if [ "$lock_pid_content" -eq "$CURRENT_SCRIPT_PID" ]; then rm -f "$LOCK_FILE"; echo "INFO: Lock file cleaned up." >> "$LOG_FILE";
        else echo "WARNING: Lock file for different PID ($lock_pid_content). Not removing." | tee -a "$LOG_FILE" "$ERROR_LOG"; fi
    else echo "INFO: Lock file already removed." >> "$LOG_FILE"; fi
}
cleanup_temp_workspace() {
    if [ "$PIPELINE_KEEP_TEMP_RUN_DIR" == "true" ]; then
        echo "INFO: PIPELINE_KEEP_TEMP_RUN_DIR is true. Skipping cleanup of main temporary workspace: ${WSL_WORK_DIR}" >> "$LOG_FILE"
        return 0
    fi
    if [ -d "$WSL_WORK_DIR" ]; then
        if [[ "$WSL_WORK_DIR" == "${PROCESSING_BASE_INSIDE_WRAPPER}/pipeline_run_"* ]]; then
            rm -rf "$WSL_WORK_DIR"; echo "INFO: Temporary workspace '$WSL_WORK_DIR' cleaned up." >> "$LOG_FILE";
        else echo "ERROR: WSL_WORK_DIR ('$WSL_WORK_DIR') unsafe. Aborting cleanup." | tee -a "$LOG_FILE" "$ERROR_LOG"; fi
    else echo "INFO: Temporary workspace '$WSL_WORK_DIR' not found." >> "$LOG_FILE"; fi
}
trap 'echo "INFO: Exit trap triggered for PID $CURRENT_SCRIPT_PID. Cleaning up..." >> "$LOG_FILE"; cleanup_temp_workspace; cleanup_lock; echo "INFO: Script exiting." >> "$LOG_FILE"; exit' INT TERM EXIT

INPUT_DIR_PARAM="$1"
OUTPUT_DIR_PARAM="$2"
if [ -z "$INPUT_DIR_PARAM" ] || [ -z "$OUTPUT_DIR_PARAM" ]; then
    echo "ERROR: INPUT_DIR and OUTPUT_DIR must be specified." | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1;
fi
echo "INFO: Input directory (container): $INPUT_DIR_PARAM" >> "$LOG_FILE"
echo "INFO: Output directory (container): $OUTPUT_DIR_PARAM" >> "$LOG_FILE"
if [ ! -d "$INPUT_DIR_PARAM" ]; then
    echo "ERROR: Input directory '$INPUT_DIR_PARAM' not found." | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1;
fi
if ! mkdir -p "$OUTPUT_DIR_PARAM" 2>/dev/null; then
    if [ ! -d "$OUTPUT_DIR_PARAM" ] || [ ! -w "$OUTPUT_DIR_PARAM" ]; then
        echo "ERROR: Output directory '$OUTPUT_DIR_PARAM' not creatable/writable." | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1;
    fi
fi

NA_PIPELINE="${SCRIPT_DIR}/na-pipeline.sh"
XML2TEXT="${SCRIPT_DIR}/xml2text.sh"
for script_to_check in "$NA_PIPELINE" "$XML2TEXT"; do
    if [ ! -f "$script_to_check" ]; then echo "ERROR: Script not found: $script_to_check" | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1; fi
    if [ ! -x "$script_to_check" ]; then echo "ERROR: Script not executable: $script_to_check" | tee -a "$LOG_FILE" "$ERROR_LOG"; exit 1; fi
done

needs_processing() {
    local source_file_path="$1" target_output_base_dir="$2" source_filename file_extension name_no_ext source_mod_time processed_file_pattern newest_destination_mod_time current_dest_mod_time
    source_filename=$(basename "$source_file_path"); file_extension="${source_filename##*.}"; name_no_ext="${source_filename%.*}"
    source_mod_time=$(stat -c %Y "$source_file_path"); processed_file_pattern="${name_no_ext}_*.$file_extension"
    if find "$target_output_base_dir" -maxdepth 1 -name "$processed_file_pattern" -print -quit | grep -q .; then
        newest_destination_mod_time=0
        for dest_file_candidate in "$target_output_base_dir"/"$processed_file_pattern"; do
            if [ -f "$dest_file_candidate" ]; then 
                current_dest_mod_time=$(stat -c %Y "$dest_file_candidate")
                if [ "$current_dest_mod_time" -gt "$newest_destination_mod_time" ]; then newest_destination_mod_time=$current_dest_mod_time; fi
            fi
        done
        if [ "$source_mod_time" -gt "$newest_destination_mod_time" ]; then echo "INFO: Source '$source_filename' newer. Processing." >> "$LOG_FILE"; return 0;
        else echo "INFO: File '$source_filename' processed & not newer." >> "$LOG_FILE"; return 1; fi
    fi
    echo "INFO: No processed version of '$source_filename' found. Processing." >> "$LOG_FILE"; return 0;
}
copy_with_date_suffix() {
    local source_file_to_copy="$1" destination_base_dir="$2" original_filename file_ext name_part date_suffix new_target_filename
    original_filename=$(basename "$source_file_to_copy"); file_ext="${original_filename##*.}"; name_part="${original_filename%.*}"
    date_suffix=$(date +"%d%m%Y"); new_target_filename="${name_part}_${date_suffix}.${file_ext}"
    mkdir -p "${destination_base_dir}" 
    echo "INFO: Copying '${source_file_to_copy}' to '${destination_base_dir}/${new_target_filename}'" >> "$LOG_FILE"
    if ! cp "${source_file_to_copy}" "${destination_base_dir}/${new_target_filename}"; then 
        echo "ERROR: Failed to copy '${source_file_to_copy}' to '${destination_base_dir}/${new_target_filename}'" | tee -a "$LOG_FILE" "$ERROR_LOG"; return 1;
    fi
    echo "INFO: Successfully copied '${source_file_to_copy}' to '${destination_base_dir}/${new_target_filename}'" >> "$LOG_FILE"; return 0;
}

echo "--- Initial Directory Scan ---" | tee -a "$LOG_FILE"
list_dir_contents_workspace "$INPUT_DIR_PARAM" "INPUT_DIR_PARAM at start of main loop"
list_dir_contents_workspace "$OUTPUT_DIR_PARAM" "OUTPUT_DIR_PARAM at start of main loop"


find "$INPUT_DIR_PARAM" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' current_processing_dir_path; do
    current_dir_name=$(basename "${current_processing_dir_path}")
    echo "" | tee -a "$LOG_FILE"
    echo "--- Processing directory: ${current_dir_name} ---" | tee -a "$LOG_FILE"
    
    item_specific_temp_workspace="${WSL_WORK_DIR}/${current_dir_name}"
    mkdir -p "${item_specific_temp_workspace}"
    echo "INFO: Item-specific temp workspace: ${item_specific_temp_workspace}" >> "$LOG_FILE"
    
    mkdir -p "${item_specific_temp_workspace}/page"
    
    echo "INFO: Copying image files from '${current_processing_dir_path}' to '${item_specific_temp_workspace}'" >> "$LOG_FILE"
    find "${current_processing_dir_path}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \) -exec cp -t "${item_specific_temp_workspace}/" {} +
    list_dir_contents_workspace "${item_specific_temp_workspace}" "item_specific_temp_workspace after image copy"

    sanitized_dir_name=$(echo "$current_dir_name" | tr ' ' '_') 
    final_item_output_dir="${OUTPUT_DIR_PARAM}/${sanitized_dir_name}"
    mkdir -p "${final_item_output_dir}"

    requires_processing_flag=false
    if [ -d "$current_processing_dir_path" ] && [ -n "$(ls -A "$current_processing_dir_path" 2>/dev/null)" ]; then
        for file_in_item_source in "${current_processing_dir_path}"/*; do
            if [ -f "$file_in_item_source" ]; then
                if needs_processing "$file_in_item_source" "${final_item_output_dir}"; then
                    requires_processing_flag=true; break;
                fi
            fi
        done
    else
        echo "INFO: Source item dir '${current_processing_dir_path}' empty/not found. Skipping." >> "$LOG_FILE"
    fi
    
    if [ "$requires_processing_flag" = true ]; then
        echo "INFO: Directory '${current_dir_name}' requires processing." | tee -a "$LOG_FILE"
        na_pipeline_temp_output_dir="${item_specific_temp_workspace}/output_from_na_pipeline"
        mkdir -p "${na_pipeline_temp_output_dir}"

        echo "INFO: Executing na-pipeline.sh. Input: '${item_specific_temp_workspace}', Output: '${na_pipeline_temp_output_dir}', CopySource: ${COPY_SOURCE_IMAGES_ENABLED}, CopyBaseline: ${COPY_BASELINE_IMAGES_ENABLED}" | tee -a "$LOG_FILE"
        
        # Call na-pipeline.sh
        # Store the actual exit status of na-pipeline.sh
        na_pipeline_actual_exit_status=0
        if ! run_with_timeout "${NA_PIPELINE} ${item_specific_temp_workspace} ${na_pipeline_temp_output_dir} ${COPY_SOURCE_IMAGES_ENABLED} ${COPY_BASELINE_IMAGES_ENABLED}" \
            "$MAX_OPERATION_TIMEOUT" "na-pipeline.sh for ${current_dir_name}" "$PIPELINE_EXEC_USER"; then
            # run_with_timeout already logs the error and its perceived exit status.
            # We capture the actual_exit_status from run_with_timeout for our own logic.
            na_pipeline_actual_exit_status=$? 
            echo "ERROR (workspace_na_pipeline.sh): na-pipeline.sh for directory ${current_dir_name} reported failure (actual exit status: $na_pipeline_actual_exit_status from run_with_timeout). See logs." | tee -a "$LOG_FILE" "$ERROR_LOG"
            # Even if na-pipeline.sh fails, we might want to attempt to see if any partial output was created
            # before skipping entirely, or decide to skip based on na_pipeline_actual_exit_status.
            # For now, if run_with_timeout indicates failure (returns non-zero), we continue.
            if [ $na_pipeline_actual_exit_status -ne 0 ]; then
                list_dir_contents_workspace "${na_pipeline_temp_output_dir}" "na_pipeline_temp_output_dir AFTER na-pipeline.sh (reported failure)"
                continue
            fi
        fi
        list_dir_contents_workspace "${na_pipeline_temp_output_dir}" "na_pipeline_temp_output_dir after na-pipeline.sh (reported success by run_with_timeout)"

        # Proceed with xml2text only if na_pipeline_temp_output_dir contains XML files
        if [ -d "${na_pipeline_temp_output_dir}" ] && [ -n "$(ls -A "${na_pipeline_temp_output_dir}"/*.xml 2>/dev/null)" ]; then
            echo "INFO: Converting XML files to text using xml2text.sh from '${na_pipeline_temp_output_dir}'" | tee -a "$LOG_FILE"
            xml2text_actual_exit_status=0
            if ! run_with_timeout "${XML2TEXT} ${na_pipeline_temp_output_dir} ${na_pipeline_temp_output_dir}" \
                900 "xml2text.sh for ${current_dir_name}" "$PIPELINE_EXEC_USER"; then
                 xml2text_actual_exit_status=$?
                 echo "ERROR (workspace_na_pipeline.sh): xml2text.sh failed for ${current_dir_name} (actual exit status: $xml2text_actual_exit_status). See logs." | tee -a "$LOG_FILE" "$ERROR_LOG"
            else
                 echo "INFO: XML to text conversion completed for ${current_dir_name}." >> "$LOG_FILE"
            fi
            list_dir_contents_workspace "${na_pipeline_temp_output_dir}" "na_pipeline_temp_output_dir after xml2text.sh"
        else
            echo "INFO: No XML files in '${na_pipeline_temp_output_dir}' after na-pipeline.sh. Skipping XML to text conversion." >> "$LOG_FILE"
        fi

        if [ -d "${na_pipeline_temp_output_dir}" ] && [ "$(ls -A "${na_pipeline_temp_output_dir}" 2>/dev/null)" ]; then
            echo "INFO: Copying all files from '${na_pipeline_temp_output_dir}' to '${final_item_output_dir}'" | tee -a "$LOG_FILE"
            for file_to_copy_from_intermediate in "${na_pipeline_temp_output_dir}/"*; do
                if [ -f "$file_to_copy_from_intermediate" ]; then
                    copy_with_date_suffix "$file_to_copy_from_intermediate" "${final_item_output_dir}"
                fi
            done
            echo "INFO: Final copy to '${final_item_output_dir}' for ${current_dir_name} completed." >> "$LOG_FILE"
            list_dir_contents_workspace "${final_item_output_dir}" "final_item_output_dir after copy_with_date_suffix"
        else
            echo "WARNING: Intermediate output dir ('${na_pipeline_temp_output_dir}') empty/not found. Nothing to copy." | tee -a "$LOG_FILE" "$ERROR_LOG"
        fi
        
        if [ "$REMOVE_PROCESSED_DIRS" = true ]; then
            echo "INFO: Checking processing in '${final_item_output_dir}' to consider removing source '${current_processing_dir_path}'" >> "$LOG_FILE"
            current_date_for_suffix=$(date +"%d%m%Y")
            processed_files_with_date_count=$(find "${final_item_output_dir}" -maxdepth 1 -type f -name "*_${current_date_for_suffix}.*" 2>/dev/null | wc -l)
            if [ "$processed_files_with_date_count" -gt 0 ]; then
                echo "INFO: Found ${processed_files_with_date_count} processed files. Attempting to remove source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                if [ ! -d "${current_processing_dir_path}" ]; then
                    echo "WARNING: Source dir to remove does not exist: '${current_processing_dir_path}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
                elif [ ! "$(ls -A "${current_processing_dir_path}" 2>/dev/null)" ]; then
                    echo "INFO: Source dir '${current_processing_dir_path}' is already empty. Removing..." >> "$LOG_FILE"
                    rm -rf "${current_processing_dir_path}" && echo "INFO: Removed empty source: '${current_processing_dir_path}'" >> "$LOG_FILE" || echo "ERROR: Failed to remove empty source '${current_processing_dir_path}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
                else
                    echo "INFO: Attempting to remove non-empty source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                    if rm -rf "${current_processing_dir_path}"; then
                        echo "INFO: Removed source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                    else
                        echo "ERROR: Failed to remove source directory '${current_processing_dir_path}'. Manual check may be needed." | tee -a "$LOG_FILE" "$ERROR_LOG"
                    fi
                fi
                if [ -d "${current_processing_dir_path}" ]; then
                    echo "WARNING: Directory still exists after removal attempt: '${current_processing_dir_path}'" | tee -a "$LOG_FILE" "$ERROR_LOG"
                    ls -la "${current_processing_dir_path}" >> "$ERROR_LOG" 
                else
                    echo "INFO: Verified removal of source: '${current_processing_dir_path}'" >> "$LOG_FILE"
                fi
            else
                echo "INFO: Skipping source removal for '${current_processing_dir_path}': No files with today's date suffix found in '${final_item_output_dir}'." >> "$LOG_FILE"
            fi
        else
            echo "INFO: Directory removal disabled for '${current_processing_dir_path}'." >> "$LOG_FILE"
        fi
    else
        echo "INFO: Skipping directory ${current_dir_name} as all files are already processed/up to date or source is empty." | tee -a "$LOG_FILE"
    fi
    
    echo "INFO: Cleaning up item-specific temporary workspace: ${item_specific_temp_workspace}" >> "$LOG_FILE"
    if [[ "$item_specific_temp_workspace" == "${WSL_WORK_DIR}/${current_dir_name}" ]] && [ -n "${current_dir_name}" ] && [ -d "${item_specific_temp_workspace}" ]; then
        rm -rf "${item_specific_temp_workspace}"
        echo "INFO: Cleaned up ${item_specific_temp_workspace}" >> "$LOG_FILE"
    else
        echo "ERROR: Item-specific workspace path unsafe ('${item_specific_temp_workspace}') or does not exist. Not removing." | tee -a "$LOG_FILE" "$ERROR_LOG"
    fi
    echo "--- Finished processing directory: ${current_dir_name} ---" | tee -a "$LOG_FILE"
done

echo "" 
echo "--- Pipeline Processing Completed: $(date) ---" | tee -a "$LOG_FILE"
