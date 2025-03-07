#!/bin/bash

echo "Starting workspace_na_pipeline.sh"
# Change working directory to script directory
cd "$(dirname "$0")"

# Configuration options
REMOVE_PROCESSED_DIRS=true  # Set to false to keep processed directories in the input location

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
    
    # Copy the file
    cp "$source_file" "$dest_dir/$new_filename"
    echo "Copied $source_file to $dest_dir/$new_filename"
}

# Process all subdirectories in INPUT_DIR
for subdir in "$INPUT_DIR"/*/ ; do
    if [ -d "$subdir" ]; then
        subdir_name=$(basename "$subdir")
        echo "Processing directory: $subdir_name"

        # Create a sanitized directory name (replace spaces with underscores)
        safe_subdir_name=$(echo "$subdir_name" | tr ' ' '_')
        
        # Create output directory for this subdirectory
        mkdir -p "$OUTPUT_DIR/$safe_subdir_name"
        
        # Check if files need processing
        process_directory=false
        for file in "$subdir"/*; do
            if [ -f "$file" ]; then
                if needs_processing "$file" "$OUTPUT_DIR/$safe_subdir_name"; then
                    process_directory=true
                    break
                fi
            fi
        done
        
        if [ "$process_directory" = true ]; then
            # Copy subdirectory to WSL work directory with sanitized name
            cp -r "$subdir" "$WSL_WORK_DIR/$safe_subdir_name"
            echo "Copied $subdir to $WSL_WORK_DIR/$safe_subdir_name"

            # Execute na-pipeline.sh on the copied directory (with quotes to handle spaces)
            ./na-pipeline.sh "$WSL_WORK_DIR/$safe_subdir_name" "$WSL_WORK_DIR/$safe_subdir_name/output"

            # Convert XML files to text files using xml2text.sh script
            ./xml2text.sh "$WSL_WORK_DIR/$safe_subdir_name/output" "$WSL_WORK_DIR/$safe_subdir_name/output"

            # Copy output files to final destination with date suffix
            if [ -d "$WSL_WORK_DIR/$safe_subdir_name/output" ]; then
                mkdir -p "$OUTPUT_DIR/$safe_subdir_name"
                
                # Copy each file with date suffix
                for file in "$WSL_WORK_DIR/$safe_subdir_name/output/"*; do
                    if [ -f "$file" ]; then
                        copy_with_date_suffix "$file" "$OUTPUT_DIR/$safe_subdir_name"
                    fi
                done
                
                echo "Copied output to $OUTPUT_DIR/$safe_subdir_name with date suffix"
            else
                echo "Warning: Output directory not found in $WSL_WORK_DIR/$safe_subdir_name"
            fi

            # Remove processed subdirectory from input directory if configured to do so
            if [ "$REMOVE_PROCESSED_DIRS" = true ]; then
                rm -rf "$INPUT_DIR/$subdir_name"
                echo "Removed processed directory from input: $INPUT_DIR/$subdir_name"
            else
                echo "Keeping processed directory in input: $INPUT_DIR/$subdir_name"
            fi

            # Clean up temporary working directory for this subdirectory
            echo "Cleaning up temporary directory: $WSL_WORK_DIR/$safe_subdir_name"
            rm -rf "$WSL_WORK_DIR/$safe_subdir_name"
        else
            echo "Skipping directory $subdir_name as all files are already processed and up to date"
        fi
    fi
done

echo "Processing completed."
