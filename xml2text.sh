#!/bin/bash

# Check if xmlstarlet is installed
if ! command -v xmlstarlet &> /dev/null; then
    echo "Error: xmlstarlet is not installed."
    echo "Please install it using one of the following commands:"
    echo "  - For Debian/Ubuntu: sudo apt-get install xmlstarlet"
    echo "  - For CentOS/RHEL: sudo yum install xmlstarlet"
    echo "  - For macOS (with Homebrew): brew install xmlstarlet"
    exit 1
fi

# Accept parameters from command line
INPUT_DIR="$1"
OUTPUT_DIR="$2"

# Check for the presence of input parameters or environment variables
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Error: Input and output directories must be specified either as arguments or environment variables."
    echo "Usage: $0 <INPUT_DIR> <OUTPUT_DIR>"
    echo "Example: $0 /path/to/xml/files /path/to/output"
    exit 1
fi

# Check if input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist or is not accessible."
    exit 1
fi

# Create OUTPUT_DIR if it does not exist
if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
    echo "Error: Cannot create output directory '$OUTPUT_DIR'. Check permissions."
    exit 1
fi

# Initialize error counter
ERROR_COUNT=0
PROCESSED_COUNT=0
XML_FILE_COUNT=0

# Check if there are any XML files to process
XML_FILES=("$INPUT_DIR"/*.xml)
if [ ! -e "${XML_FILES[0]}" ]; then
    echo "Warning: No XML files found in '$INPUT_DIR'"
    exit 0
fi

# Process all XML files in INPUT_DIR
for xml_file in "$INPUT_DIR"/*.xml; do
    if [ -f "$xml_file" ]; then
        XML_FILE_COUNT=$((XML_FILE_COUNT + 1))
        filename=$(basename -- "$xml_file")
        filename_no_ext="${filename%.*}"
        output_file="$OUTPUT_DIR/${filename_no_ext}.txt"
        
        echo "Processing: $filename"
        
        # Check if XML file is readable
        if [ ! -r "$xml_file" ]; then
            echo "Error: Cannot read file '$xml_file'. Check permissions."
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi
        
        # Extract text from XML using xpath, preserving complete lines
        # This command will:
        # 1. Find all TextLine elements in reading order
        # 2. Extract the complete line text from TextEquiv/Unicode
        # 3. Preserve line structure
        xmlstarlet sel -N p="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15" \
            -t -m "//p:TextLine" \
            -v "p:TextEquiv/p:Unicode" \
            -n "$xml_file" > "$output_file" 2>/tmp/xml_error.log
        
        if [ $? -eq 0 ]; then
            echo "Created: $output_file"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
        else
            ERROR_MSG=$(cat /tmp/xml_error.log)
            echo "Error processing $filename: $ERROR_MSG"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            # Create an empty output file to indicate processing was attempted
            touch "$output_file"
            echo "XML processing error. See log for details." > "$output_file"
        fi
    fi
done

# Report summary
echo "XML to text conversion summary:"
echo "  Total XML files found: $XML_FILE_COUNT"
echo "  Successfully processed: $PROCESSED_COUNT"
echo "  Errors encountered: $ERROR_COUNT"

# Return appropriate exit code
if [ $ERROR_COUNT -gt 0 ]; then
    echo "Warning: Some files could not be processed. Check the output for details."
    exit 2
fi

echo "Processing completed successfully."
exit 0 