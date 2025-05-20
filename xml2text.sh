#!/bin/bash

# Check if xmlstarlet is installed
if ! command -v xmlstarlet &> /dev/null; then
    echo "ERROR (xml2text.sh): xmlstarlet is not installed. Please install it." >&2
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

echo "INFO (xml2text.sh): Starting XML to text conversion."
echo "INFO (xml2text.sh): Input directory: '$INPUT_DIR'"
echo "INFO (xml2text.sh): Output directory: '$OUTPUT_DIR'"

if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "ERROR (xml2text.sh): Input and output directories must be specified." >&2
    exit 1
fi
if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR (xml2text.sh): Input directory '$INPUT_DIR' does not exist or is not accessible." >&2
    exit 1
fi
if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
    echo "ERROR (xml2text.sh): Cannot create output directory '$OUTPUT_DIR'. Check permissions." >&2
    exit 1
fi

ERROR_COUNT=0
PROCESSED_COUNT=0
EMPTY_OUTPUT_COUNT=0
XML_FILE_COUNT=$(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.xml" 2>/dev/null | wc -l)

echo "INFO (xml2text.sh): Found $XML_FILE_COUNT XML files in '$INPUT_DIR'."

if [ "$XML_FILE_COUNT" -eq 0 ]; then
    echo "WARNING (xml2text.sh): No XML files found in '$INPUT_DIR'. Nothing to process."
    exit 0 # Not an error if no input files
fi

TEMP_XML_ERROR_LOG="/tmp/xmlstarlet_error_$(date +%s%N).log"

for xml_file in "$INPUT_DIR"/*.xml; do
    if [ -f "$xml_file" ] || [ -L "$xml_file" ]; then # Process regular files or symlinks
        filename=$(basename -- "$xml_file")
        filename_no_ext="${filename%.*}"
        output_file="$OUTPUT_DIR/${filename_no_ext}.txt"
        
        echo "INFO (xml2text.sh): Processing: '$filename' -> '$output_file'"
        
        if [ ! -r "$xml_file" ]; then
            echo "ERROR (xml2text.sh): Cannot read file '$xml_file'. Check permissions." >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi
        
        # Attempt with common PAGE XML namespaces
        # Try 2013 namespace first
        echo "DEBUG (xml2text.sh): Trying xmlstarlet with 2013 namespace for '$filename'"
        xmlstarlet sel -N p="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15" \
            -t -m "//p:TextRegion/p:TextLine" -v "p:TextEquiv/p:Unicode" -n "$xml_file" > "$output_file" 2>"$TEMP_XML_ERROR_LOG"
        xmlstarlet_exit_code=$?

        # If 2013 failed or produced empty output, try 2019 namespace
        if [ $xmlstarlet_exit_code -ne 0 ] || ! [ -s "$output_file" ]; then
            echo "DEBUG (xml2text.sh): 2013 namespace failed or produced empty output for '$filename'. Trying 2019 namespace."
            cat "$TEMP_XML_ERROR_LOG" >&2 # Show error from previous attempt
            xmlstarlet sel -N p="http://schema.primaresearch.org/PAGE/gts/pagecontent/2019-07-15" \
                -t -m "//p:TextRegion/p:TextLine" -v "p:TextEquiv/p:Unicode" -n "$xml_file" > "$output_file" 2>"$TEMP_XML_ERROR_LOG"
            xmlstarlet_exit_code=$?
        fi
        
        # If still failed or empty, try without explicit namespace (less reliable but a fallback)
        if [ $xmlstarlet_exit_code -ne 0 ] || ! [ -s "$output_file" ]; then
            echo "DEBUG (xml2text.sh): 2019 namespace also failed or produced empty output for '$filename'. Trying without namespace."
            cat "$TEMP_XML_ERROR_LOG" >&2 # Show error from previous attempt
            xmlstarlet sel -t -m "//*[local-name()='TextLine']" -v "*[local-name()='TextEquiv']/*[local-name()='Unicode']" -n "$xml_file" > "$output_file" 2>"$TEMP_XML_ERROR_LOG"
            xmlstarlet_exit_code=$?
        fi

        if [ $xmlstarlet_exit_code -eq 0 ]; then
            if [ -s "$output_file" ]; then
                echo "INFO (xml2text.sh): Created and populated: '$output_file'"
                PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
            else
                echo "WARNING (xml2text.sh): Created an EMPTY file: '$output_file' for '$filename'. xmlstarlet might not have found TextLine/Unicode elements." >&2
                # Optionally, log the content of xml_error.log here too
                if [ -s "$TEMP_XML_ERROR_LOG" ]; then
                    echo "DEBUG (xml2text.sh): xmlstarlet stderr for '$filename':" >&2
                    cat "$TEMP_XML_ERROR_LOG" >&2
                fi
                EMPTY_OUTPUT_COUNT=$((EMPTY_OUTPUT_COUNT + 1))
                # Consider if an empty output for a found XML is an error
                # ERROR_COUNT=$((ERROR_COUNT + 1)) 
            fi
        else
            ERROR_MSG=$(cat "$TEMP_XML_ERROR_LOG")
            echo "ERROR (xml2text.sh): xmlstarlet failed for '$filename'. Exit code: $xmlstarlet_exit_code. Message: $ERROR_MSG" >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            # Ensure an empty .txt file is created so it's clear an attempt was made
            # but also indicates failure by not having content or having an error message.
            echo "XMLSTARLET_PROCESSING_ERROR for $filename. See main logs." > "$output_file"
        fi
        rm -f "$TEMP_XML_ERROR_LOG" # Clean up temp error log
    fi
done

echo "--- XML to text conversion summary (xml2text.sh) ---"
echo "Total XML files found: $XML_FILE_COUNT"
echo "Successfully processed (non-empty TXT): $PROCESSED_COUNT"
echo "Produced empty TXT files: $EMPTY_OUTPUT_COUNT"
echo "Errors encountered (xmlstarlet non-zero exit): $ERROR_COUNT"
echo "--- End of xml2text.sh summary ---"

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "ERROR (xml2text.sh): Finished with $ERROR_COUNT errors." >&2
    exit 1 # Exit with error if any xmlstarlet command failed
elif [ "$XML_FILE_COUNT" -gt 0 ] && [ "$PROCESSED_COUNT" -eq 0 ]; then
    # This case means XML files were found, no hard errors from xmlstarlet, but no non-empty TXT files were produced.
    echo "WARNING (xml2text.sh): Processed $XML_FILE_COUNT XML files, but all resulting TXT files were empty. Check XPath/namespaces." >&2
    exit 1 # Consider this a failure state as well
fi

echo "INFO (xml2text.sh): Processing completed."
exit 0 
