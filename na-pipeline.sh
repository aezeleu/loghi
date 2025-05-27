#!/bin/bash
VERSION=1.3.7 # Assuming this is the correct version for your tools
set -e

# Arguments:
# $1: SRC - Source directory for processing
# $2: OUT - Output directory for this script's results
# $3: COPY_SOURCE_IMAGES_FLAG - "true" or "false" to copy original source images
# $4: COPY_BASELINE_IMAGES_FLAG - "true" or "false" to copy generated baseline images

# Function to list directory contents for debugging
list_dir_contents() {
    local dir_path="$1"
    local description="$2"
    echo "DEBUG_LOG (na-pipeline.sh): Listing contents of ${description} ('${dir_path}'):"
    if [ -d "$dir_path" ]; then
        # Using find for better control and to avoid issues with too many files for ls -R
        find "$dir_path" -ls || echo "DEBUG_LOG (na-pipeline.sh): Failed to list '${dir_path}' or directory is empty (using find)."
    else
        echo "DEBUG_LOG (na-pipeline.sh): Directory '${dir_path}' does not exist for listing."
    fi
    echo "--- End of listing for ${description} ---"
}

# Check if source directory is accessible
check_source_directory() {
    local src_path="$1" 
    if [ ! -d "$src_path" ]; then
        echo "ERROR (na-pipeline.sh): Source directory '$src_path' does not exist or is not accessible." >&2
        exit 1
    fi
    if ! ls "$src_path" >/dev/null 2>&1; then
        echo "ERROR (na-pipeline.sh): Cannot access contents of source directory '$src_path'." >&2
        exit 1
    fi
}

# --- Argument Parsing & Initial Setup ---
if [ -z "$1" ]; then echo "ERROR (na-pipeline.sh): Missing SRC directory (arg 1)" >&2 && exit 1; fi;
if [ -z "$2" ]; then echo "ERROR (na-pipeline.sh): Missing OUT directory (arg 2)" >&2 && exit 1; fi;
if [ -z "$3" ]; then echo "ERROR (na-pipeline.sh): Missing COPY_SOURCE_IMAGES_FLAG (arg 3 - true/false)" >&2 && exit 1; fi;
if [ -z "$4" ]; then echo "ERROR (na-pipeline.sh): Missing COPY_BASELINE_IMAGES_FLAG (arg 4 - true/false)" >&2 && exit 1; fi;

SRC="$1"
OUT="$2"
COPY_SOURCE_IMAGES_FLAG="$3"
COPY_BASELINE_IMAGES_FLAG="$4"

echo "INFO (na-pipeline.sh): Source (SRC): ${SRC}"
echo "INFO (na-pipeline.sh): Output (OUT): ${OUT}"
echo "INFO (na-pipeline.sh): COPY_SOURCE_IMAGES_FLAG: ${COPY_SOURCE_IMAGES_FLAG}"
echo "INFO (na-pipeline.sh): COPY_BASELINE_IMAGES_FLAG: ${COPY_BASELINE_IMAGES_FLAG}"

# --- !! Docker Daemon Sanity Check !! ---
echo "INFO (na-pipeline.sh): Performing Docker daemon sanity check..."
if ! docker info > /dev/null 2>&1; then
    echo "ERROR (na-pipeline.sh): Docker daemon is NOT responsive at the beginning of na-pipeline.sh." >&2
    echo "ERROR (na-pipeline.sh): This indicates the inner dockerd may have stopped or failed after initial container startup." >&2
    echo "Attempting to display last 50 lines of /var/log/dockerd.log (from within loghi-wrapper):" >&2
    cat /var/log/dockerd.log | tail -n 50 >&2 || echo "ERROR (na-pipeline.sh): Could not read /var/log/dockerd.log." >&2
    exit 1 
else
    echo "INFO (na-pipeline.sh): Docker daemon IS responsive at the beginning of na-pipeline.sh."
fi
# --- !! End Docker Daemon Sanity Check !! ---


check_source_directory "$1"
tmpdir=$(mktemp -d) 
echo "INFO (na-pipeline.sh): Temporary directory for this run: $tmpdir"


# --- Configuration ---
STOPONERROR=1
BASELINELAYPA=1
HTRLOGHI=1
RECALCULATEREADINGORDER=1
DETECTLANGUAGE=1
SPLITWORDS=1
BEAMWIDTH=1
GPU=0 

if [ -z "$BASEDIR" ]; then
    BASEDIR=/app 
    echo "INFO (na-pipeline.sh): BASEDIR for models set to '$BASEDIR'."
fi
LAYPAMODEL="${BASEDIR}/laypa/general/baseline/config.yaml"
LAYPAMODELWEIGHTS="${BASEDIR}/laypa/general/baseline/model_best_mIoU.pth"
HTRLOGHIMODEL="${BASEDIR}/loghi-htr/generic-2023-02-15"
RECALCULATEREADINGORDERBORDERMARGIN=50
RECALCULATEREADINGORDERCLEANBORDERS=0
RECALCULATEREADINGORDERTHREADS=4 

DOCKERLOGHITOOLING="loghi/docker.loghi-tooling:${VERSION}" 
DOCKERLAYPA="loghi/docker.laypa:${VERSION}"
DOCKERLOGHIHTR="loghi/docker.htr:${VERSION}"
USE2013NAMESPACE=" -use_2013_namespace "


DOCKERGPUPARAMS="" 
if [[ $GPU -gt -1 ]]; then
    DOCKERGPUPARAMS="--gpus device=${GPU}"
    echo "INFO (na-pipeline.sh): Attempting to use GPU ${GPU}. DOCKERGPUPARAMS=${DOCKERGPUPARAMS}"
else
    echo "INFO (na-pipeline.sh): Using CPU. DOCKERGPUPARAMS will be empty."
fi

mkdir -p "$OUT"
mkdir -p "$tmpdir/imagesnippets/"
mkdir -p "$tmpdir/linedetection" 
mkdir -p "$tmpdir/output_htr_internal" 

find "$SRC" -name '*.done' -exec rm -f "{}" \;

CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
echo "INFO (na-pipeline.sh): Docker containers will be run as UID: $CURRENT_UID, GID: $CURRENT_GID"
list_dir_contents "$SRC" "Initial SRC"

# --- Laypa Baseline Detection ---
if [[ $BASELINELAYPA -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Starting Laypa baseline detection."
    laypa_input_dir="$SRC"
    laypa_output_dir="$SRC" 
    LAYPADIR_MODEL_BASE="$(dirname "${LAYPAMODEL}")"

    echo "INFO (na-pipeline.sh): Laypa Input Dir: $laypa_input_dir"
    echo "INFO (na-pipeline.sh): Laypa Output Dir (for page/ XMLs): $laypa_output_dir"
    echo "INFO (na-pipeline.sh): Laypa Model Base Dir (for volume mount): $LAYPADIR_MODEL_BASE"

    if [ ! -f "$LAYPAMODEL" ] || [ ! -f "$LAYPAMODELWEIGHTS" ]; then
        echo "ERROR (na-pipeline.sh): Laypa model or weights not found at expected paths:" >&2; exit 1;
    fi
    if ! docker image inspect "$DOCKERLAYPA" > /dev/null 2>&1; then
        echo "WARNING (na-pipeline.sh): Docker image $DOCKERLAYPA not found. Pulling..." >&2
        docker pull "$DOCKERLAYPA" || (echo "ERROR (na-pipeline.sh): Failed to pull $DOCKERLAYPA" >&2 && exit 1)
    fi

    docker run $DOCKERGPUPARAMS --rm -u "$CURRENT_UID:$CURRENT_GID" -m 32000m --shm-size 10240m \
        -v "$LAYPADIR_MODEL_BASE:$LAYPADIR_MODEL_BASE:ro" \
        -v "$laypa_input_dir:$laypa_input_dir:rw" \
        -v "$laypa_output_dir:$laypa_output_dir:rw" \
        "$DOCKERLAYPA" \
        python run.py \
        -c "$LAYPAMODEL" \
        -i "$laypa_input_dir" \
        -o "$laypa_output_dir" \
        --opts MODEL.WEIGHTS "" TEST.WEIGHTS "$LAYPAMODELWEIGHTS" 2>&1 | tee -a "$tmpdir/log_laypa.txt"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then 
        echo "ERROR (na-pipeline.sh): Laypa baseline detection failed. Check $tmpdir/log_laypa.txt" >&2
        if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
    fi
    echo "INFO (na-pipeline.sh): Laypa baseline detection finished."
    list_dir_contents "${laypa_output_dir}/page" "Laypa output in SRC/page"

    page_xml_dir_for_minion="${laypa_output_dir}/page" 
    if [ -d "$page_xml_dir_for_minion" ] && [ -n "$(ls -A "$page_xml_dir_for_minion"/*.xml 2>/dev/null)" ]; then
        echo "INFO (na-pipeline.sh): Running MinionExtractBaselines..."
        docker run --rm -u "$CURRENT_UID:$CURRENT_GID" \
            -v "$page_xml_dir_for_minion:$page_xml_dir_for_minion:rw" \
            "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionExtractBaselines \
            -input_path_png "$page_xml_dir_for_minion/" \
            -input_path_page "$page_xml_dir_for_minion/" \
            -output_path_page "$page_xml_dir_for_minion/" \
            -as_single_region true $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_minionextract.txt"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "ERROR (na-pipeline.sh): MinionExtractBaselines failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionExtractBaselines finished."
        list_dir_contents "$page_xml_dir_for_minion" "SRC/page after MinionExtractBaselines"
    else
        echo "WARNING (na-pipeline.sh): Laypa did not create '$page_xml_dir_for_minion' or no XMLs found. Skipping MinionExtractBaselines." >&2
    fi
fi

# --- Loghi HTR ---
if [[ $HTRLOGHI -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Starting Loghi HTR process."
    page_xml_dir_htr_cut="$SRC/page" 
    if [ ! -d "$page_xml_dir_htr_cut" ] || [ -z "$(ls -A "$page_xml_dir_htr_cut"/*.xml 2>/dev/null)" ]; then
         echo "WARNING (na-pipeline.sh): Page XML dir '$page_xml_dir_htr_cut' not found or no XMLs. Skipping MinionCut." >&2
    else
        echo "INFO (na-pipeline.sh): Running MinionCutFromImageBasedOnPageXMLNew..."
        docker run -u "$CURRENT_UID:$CURRENT_GID" --rm \
            -v "$SRC:$SRC:rw" \
            -v "$tmpdir/imagesnippets/:$tmpdir/imagesnippets/:rw" \
            "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionCutFromImageBasedOnPageXMLNew \
            -input_path "$SRC" \
            -outputbase "$tmpdir/imagesnippets/" \
            -output_type png \
            -channels 4 \
            -threads $RECALCULATEREADINGORDERTHREADS $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_minioncut.txt"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "ERROR (na-pipeline.sh): MinionCutFromImageBasedOnPageXMLNew failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionCutFromImageBasedOnPageXMLNew finished."
        list_dir_contents "$tmpdir/imagesnippets/" "HTR image snippets"
    fi 

    find "$tmpdir/imagesnippets/" -type f -name '*.png' > "$tmpdir/lines.txt"
    echo "DEBUG_LOG (na-pipeline.sh): Content of lines.txt for HTR:"
    cat "$tmpdir/lines.txt" || echo "DEBUG_LOG (na-pipeline.sh): lines.txt is empty or unreadable."
    
    if [ ! -s "$tmpdir/lines.txt" ]; then
        echo "WARNING (na-pipeline.sh): No image snippets for HTR (lines.txt is empty). HTR will not run." >&2
    else
        LOGHIDIR_MODEL_BASE="$(dirname "${HTRLOGHIMODEL}")"
        if [ ! -f "$HTRLOGHIMODEL/charlist.txt" ] || [ ! -d "$HTRLOGHIMODEL" ]; then
             echo "ERROR (na-pipeline.sh): HTR model/charlist not found." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        if ! docker image inspect "$DOCKERLOGHIHTR" > /dev/null 2>&1; then
            echo "WARNING (na-pipeline.sh): Docker image $DOCKERLOGHIHTR not found. Pulling..." >&2
            docker pull "$DOCKERLOGHIHTR" || (echo "ERROR (na-pipeline.sh): Failed to pull $DOCKERLOGHIHTR" >&2 && exit 1)
        fi
        echo "INFO (na-pipeline.sh): Running Loghi HTR..."
        docker run $DOCKERGPUPARAMS -u "$CURRENT_UID:$CURRENT_GID" --rm -m 32000m --shm-size 10240m \
            -v "$tmpdir:$tmpdir:rw" \
            -v "$LOGHIDIR_MODEL_BASE:$LOGHIDIR_MODEL_BASE:ro" \
            "$DOCKERLOGHIHTR" \
            bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 python3 /src/loghi-htr/src/main.py \
            --do_inference --existing_model $HTRLOGHIMODEL --batch_size 64 --use_mask \
            --inference_list $tmpdir/lines.txt --results_file $tmpdir/results.txt \
            --charlist $HTRLOGHIMODEL/charlist.txt --gpu $GPU \
            --output $tmpdir/output_htr_internal/ \
            --config_file_output $tmpdir/output_htr_internal/config.json \
            --beam_width $BEAMWIDTH" 2>&1 | tee -a "$tmpdir/log_htr.txt"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "ERROR (na-pipeline.sh): Loghi HTR failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): Loghi HTR finished."
        echo "DEBUG_LOG (na-pipeline.sh): HTR results file ($tmpdir/results.txt) content (first 5 lines):"
        head -n 5 "$tmpdir/results.txt" || echo "DEBUG_LOG (na-pipeline.sh): results.txt empty or unreadable."

        if [ ! -f "$tmpdir/results.txt" ]; then
             echo "WARNING (na-pipeline.sh): HTR results file not found. Skipping merge." >&2
        elif [ ! -d "$SRC/page" ]; then
             echo "WARNING (na-pipeline.sh): Page XML dir '$SRC/page' not found for merging. Skipping merge." >&2
        else
            echo "INFO (na-pipeline.sh): Running MinionLoghiHTRMergePageXML..."
            docker run -u "$CURRENT_UID:$CURRENT_GID" --rm \
                -v "$LOGHIDIR_MODEL_BASE:$LOGHIDIR_MODEL_BASE:ro" \
                -v "$SRC/page:$SRC/page:rw" \
                -v "$tmpdir:$tmpdir:ro" \
                "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionLoghiHTRMergePageXML \
                -input_path "$SRC/page" -results_file "$tmpdir/results.txt" \
                -config_file "$HTRLOGHIMODEL/config.json" \
                -htr_code_config_file "$tmpdir/output_htr_internal/config.json" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_minionmerge.txt"
            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                echo "ERROR (na-pipeline.sh): MinionLoghiHTRMergePageXML failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
            fi
            echo "INFO (na-pipeline.sh): MinionLoghiHTRMergePageXML finished."
            list_dir_contents "$SRC/page" "SRC/page after HTR Merge"
        fi
    fi 
fi 

# --- Post-processing Steps ---
if [ -d "$SRC/page" ] && [ -n "$(ls -A "$SRC/page"/*.xml 2>/dev/null)" ]; then
    if [[ $RECALCULATEREADINGORDER -eq 1 ]]; then
        echo "INFO (na-pipeline.sh): Recalculating reading order for XMLs in $SRC/page/"
        page_dir_recalc="$SRC/page/" 
        # 'local' is fine for this array as it's defined and used immediately within this specific if-block
        recalc_cmd_args_array=( 
            /src/loghi-tooling/minions/target/appassembler/bin/MinionRecalculateReadingOrderNew
            -input_dir "$page_dir_recalc" -border_margin "$RECALCULATEREADINGORDERBORDERMARGIN"
            -threads "$RECALCULATEREADINGORDERTHREADS" $USE2013NAMESPACE
        )
        if [[ $RECALCULATEREADINGORDERCLEANBORDERS -eq 1 ]]; then recalc_cmd_args_array+=("-clean_borders"); fi
        docker run -u "$CURRENT_UID:$CURRENT_GID" --rm -v "$page_dir_recalc:$page_dir_recalc:rw" "$DOCKERLOGHITOOLING" "${recalc_cmd_args_array[@]}" 2>&1 | tee -a "$tmpdir/log_recalcorder.txt"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then echo "ERROR (na-pipeline.sh): MinionRecalculateReadingOrderNew failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi; fi
        echo "INFO (na-pipeline.sh): MinionRecalculateReadingOrderNew finished."
        list_dir_contents "$page_dir_recalc" "SRC/page after RecalculateReadingOrder"
    fi

    if [[ $DETECTLANGUAGE -eq 1 ]]; then
        echo "INFO (na-pipeline.sh): Detecting language for XMLs in $SRC/page/"
        page_dir_lang="$SRC/page/" 
        docker run -u "$CURRENT_UID:$CURRENT_GID" --rm -v "$page_dir_lang:$page_dir_lang:rw" "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionDetectLanguageOfPageXml \
            -page "$page_dir_lang" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_detectlang.txt"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then echo "ERROR (na-pipeline.sh): MinionDetectLanguageOfPageXml failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi; fi
        echo "INFO (na-pipeline.sh): MinionDetectLanguageOfPageXml finished."
        list_dir_contents "$page_dir_lang" "SRC/page after DetectLanguage"
    fi

    if [[ $SPLITWORDS -eq 1 ]]; then
        echo "INFO (na-pipeline.sh): Splitting words for XMLs in $SRC/page/"
        page_dir_split="$SRC/page/" 
        docker run -u "$CURRENT_UID:$CURRENT_GID" --rm -v "$page_dir_split:$page_dir_split:rw" "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionSplitPageXMLTextLineIntoWords \
            -input_path "$page_dir_split" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_splitwords.txt"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then echo "ERROR (na-pipeline.sh): MinionSplitPageXMLTextLineIntoWords failed." >&2; if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi; fi
        echo "INFO (na-pipeline.sh): MinionSplitPageXMLTextLineIntoWords finished."
        list_dir_contents "$page_dir_split" "SRC/page after SplitWords"
    fi
else
    echo "WARNING (na-pipeline.sh): No XML files found in $SRC/page. Skipping post-processing." >&2
fi

# --- Final Output Assembly to $OUT directory ---
echo "INFO (na-pipeline.sh): Assembling final output to directory: $OUT"
mkdir -p "$OUT" 
list_dir_contents "$SRC" "SRC before final copy"
list_dir_contents "$SRC/page" "SRC/page before final copy (if it exists)"

# 1. Conditionally copy original source images
if [ "$COPY_SOURCE_IMAGES_FLAG" == "true" ]; then
    echo "INFO (na-pipeline.sh): Copying original source images from $SRC to $OUT"
    find "$SRC" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \) -exec cp -v -p {} "$OUT/" \;
else
    echo "INFO (na-pipeline.sh): Skipping copy of original source images."
fi

# 2. Always copy PageXML files (if they exist)
if [ -d "$SRC/page" ]; then
    echo "INFO (na-pipeline.sh): Copying PageXML files (*.xml) from $SRC/page to $OUT"
    find "$SRC/page" -maxdepth 1 -type f -name "*.xml" -exec cp -v -p {} "$OUT/" \;
else
    echo "WARNING (na-pipeline.sh): No $SRC/page directory to copy XMLs from." >&2
fi

# 3. Conditionally copy baseline images (generated PNGs in page/ directory)
if [ "$COPY_BASELINE_IMAGES_FLAG" == "true" ]; then
    if [ -d "$SRC/page" ]; then
        echo "INFO (na-pipeline.sh): Copying generated baseline PNG images from $SRC/page to $OUT"
        find "$SRC/page" -maxdepth 1 -type f -name "*.png" -print0 | while IFS= read -r -d $'\0' baseline_png_file; do
            baseline_png_basename=$(basename "$baseline_png_file")
            target_baseline_png_name="$baseline_png_basename"
            original_source_image_if_png="$SRC/$baseline_png_basename" 
            if [ "$COPY_SOURCE_IMAGES_FLAG" == "true" ] && [ -f "$original_source_image_if_png" ]; then
                 target_baseline_png_name="${baseline_png_basename%.png}_baseline.png"
                 echo "INFO (na-pipeline.sh): Renaming baseline '$baseline_png_basename' to '$target_baseline_png_name' to avoid conflict."
            fi
            cp -v -p "$baseline_png_file" "$OUT/$target_baseline_png_name"
        done
    else
        echo "WARNING (na-pipeline.sh): No $SRC/page directory to copy baseline PNGs from." >&2
    fi
else
    echo "INFO (na-pipeline.sh): Skipping copy of baseline images."
fi
list_dir_contents "$OUT" "Final content of OUT directory (set by na-pipeline.sh)"

echo "INFO (na-pipeline.sh): Cleaning up internal temporary directory: $tmpdir"
rm -rf "$tmpdir"

echo "INFO (na-pipeline.sh): na-pipeline.sh finished successfully."
exit 0 # Explicitly exit with 0 on success
