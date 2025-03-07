#!/bin/bash

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

# Create OUTPUT_DIR if it does not exist
mkdir -p "$OUTPUT_DIR"

# Process all XML files in INPUT_DIR
for xml_file in "$INPUT_DIR"/*.xml; do
    if [ -f "$xml_file" ]; then
        filename=$(basename -- "$xml_file")
        filename_no_ext="${filename%.*}"
        output_file="$OUTPUT_DIR/${filename_no_ext}.txt"
        
        echo "Processing: $filename"
        
        # Extract text from XML using xpath, preserving complete lines
        # This command will:
        # 1. Find all TextLine elements in reading order
        # 2. Extract the complete line text from TextEquiv/Unicode
        # 3. Preserve line structure
        xmlstarlet sel -N p="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15" \
            -t -m "//p:TextLine" \
            -v "p:TextEquiv/p:Unicode" \
            -n "$xml_file" > "$output_file"
        
        if [ $? -eq 0 ]; then
            echo "Created: $output_file"
        else
            echo "Error processing $filename"
        fi
    fi
done

echo "Processing completed." 