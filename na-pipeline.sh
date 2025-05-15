#!/bin/bash
VERSION=1.3.7 # Assuming this is the correct version for your tools
set -e

# Check if source directory is accessible
check_source_directory() {
    local src_path="$1" # 'local' is correct here as it's inside a function
    if [ ! -d "$src_path" ]; then
        echo "ERROR (na-pipeline.sh): Source directory '$src_path' does not exist or is not accessible."
        exit 1
    fi
    if ! ls "$src_path" >/dev/null 2>&1; then
        echo "ERROR (na-pipeline.sh): Cannot access contents of source directory '$src_path'."
        exit 1
    fi
}

# Stop on error, if set to 1 will exit program if any of the docker commands fail
STOPONERROR=1

# set to 1 if you want to enable, 0 otherwise, select just one
BASELINELAYPA=1

# Set the base directory to where your models are located *inside the loghi-wrapper container*.
if [ -z "$BASEDIR" ]; then
    BASEDIR=/app 
    echo "INFO (na-pipeline.sh): BASEDIR for models set to '$BASEDIR'. Ensure this is correct."
fi

LAYPAMODEL="${BASEDIR}/laypa/general/baseline/config.yaml"
LAYPAMODELWEIGHTS="${BASEDIR}/laypa/general/baseline/model_best_mIoU.pth"

HTRLOGHI=1
HTRLOGHIMODEL="${BASEDIR}/loghi-htr/generic-2023-02-15"

RECALCULATEREADINGORDER=1
RECALCULATEREADINGORDERBORDERMARGIN=50
RECALCULATEREADINGORDERCLEANBORDERS=0
RECALCULATEREADINGORDERTHREADS=4 

DETECTLANGUAGE=1
SPLITWORDS=1
BEAMWIDTH=1

# --- GPU MODE CONFIGURATION ---
GPU=0 
echo "INFO (na-pipeline.sh): Configured for GPU mode (GPU=${GPU}). Ensure DinD environment supports GPU passthrough."

DOCKERLOGHITOOLING="loghi/docker.loghi-tooling:${VERSION}" 
DOCKERLAYPA="loghi/docker.laypa:${VERSION}"
DOCKERLOGHIHTR="loghi/docker.htr:${VERSION}"
USE2013NAMESPACE=" -use_2013_namespace "

if [ -z "$1" ]; then echo "ERROR (na-pipeline.sh): please provide path to images to be HTR-ed" && exit 1; fi;
if [ -z "$2" ]; then echo "ERROR (na-pipeline.sh): please provide path to result directory" && exit 1; fi;

check_source_directory "$1"

tmpdir=$(mktemp -d) 
echo "INFO (na-pipeline.sh): Temporary directory for this run: $tmpdir"

DOCKERGPUPARAMS="" 
if [[ $GPU -gt -1 ]]; then
    DOCKERGPUPARAMS="--gpus device=${GPU}"
    echo "INFO (na-pipeline.sh): Attempting to use GPU ${GPU}. DOCKERGPUPARAMS=${DOCKERGPUPARAMS}"
else
    echo "INFO (na-pipeline.sh): Using CPU. DOCKERGPUPARAMS will be empty."
fi

SRC="$1" 
OUT="$2" 
echo "INFO (na-pipeline.sh): Source (SRC): ${SRC}"
echo "INFO (na-pipeline.sh): Output (OUT): ${OUT}"

mkdir -p "$OUT"

mkdir -p "$tmpdir/imagesnippets/"
mkdir -p "$tmpdir/linedetection" 
mkdir -p "$tmpdir/output_htr_internal" 

find "$SRC" -name '*.done' -exec rm -f "{}" \;

CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
echo "INFO (na-pipeline.sh): Docker containers will be run as UID: $CURRENT_UID, GID: $CURRENT_GID"

if [[ $BASELINELAYPA -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Starting Laypa baseline detection."
    laypa_input_dir="$SRC"
    laypa_output_dir="$SRC" 
    LAYPADIR_MODEL_BASE="$(dirname "${LAYPAMODEL}")"

    echo "INFO (na-pipeline.sh): Laypa Input Dir: $laypa_input_dir"
    echo "INFO (na-pipeline.sh): Laypa Output Dir (for page/ XMLs): $laypa_output_dir"
    echo "INFO (na-pipeline.sh): Laypa Model Base Dir (for volume mount): $LAYPADIR_MODEL_BASE"
    echo "INFO (na-pipeline.sh): Laypa Config: $LAYPAMODEL"
    echo "INFO (na-pipeline.sh): Laypa Weights: $LAYPAMODELWEIGHTS"

    if [ ! -f "$LAYPAMODEL" ] || [ ! -f "$LAYPAMODELWEIGHTS" ]; then
        echo "ERROR (na-pipeline.sh): Laypa model or weights not found at expected paths:"
        echo "  Config: $LAYPAMODEL"
        echo "  Weights: $LAYPAMODELWEIGHTS"
        echo "  Please check BASEDIR and model paths in na-pipeline.sh."
        if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
    fi
    
    if ! docker image inspect "$DOCKERLAYPA" > /dev/null 2>&1; then
        echo "WARNING (na-pipeline.sh): Docker image $DOCKERLAYPA not found by inner Docker daemon. Attempting to pull..."
        docker pull "$DOCKERLAYPA" || (echo "ERROR (na-pipeline.sh): Failed to pull $DOCKERLAYPA" && exit 1)
    fi

    if ! docker run $DOCKERGPUPARAMS --rm -u "$CURRENT_UID:$CURRENT_GID" -m 32000m --shm-size 10240m \
        -v "$LAYPADIR_MODEL_BASE:$LAYPADIR_MODEL_BASE:ro" \
        -v "$laypa_input_dir:$laypa_input_dir:rw" \
        -v "$laypa_output_dir:$laypa_output_dir:rw" \
        "$DOCKERLAYPA" \
        python run.py \
        -c "$LAYPAMODEL" \
        -i "$laypa_input_dir" \
        -o "$laypa_output_dir" \
        --opts MODEL.WEIGHTS "" TEST.WEIGHTS "$LAYPAMODELWEIGHTS" 2>&1 | tee -a "$tmpdir/log_laypa.txt"; then
        echo "ERROR (na-pipeline.sh): Laypa baseline detection failed. Check $tmpdir/log_laypa.txt"
        if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
    fi
    echo "INFO (na-pipeline.sh): Laypa baseline detection finished."

    page_xml_dir_for_minion="${laypa_output_dir}/page" 
    if [ ! -d "$page_xml_dir_for_minion" ]; then
        echo "ERROR (na-pipeline.sh): Laypa did not create the expected directory: $page_xml_dir_for_minion. This means no baselines were detected or Laypa failed silently."
    else
        echo "INFO (na-pipeline.sh): Running MinionExtractBaselines..."
        if ! docker run --rm -u "$CURRENT_UID:$CURRENT_GID" \
            -v "$page_xml_dir_for_minion:$page_xml_dir_for_minion:rw" \
            "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionExtractBaselines \
            -input_path_png "$page_xml_dir_for_minion/" \
            -input_path_page "$page_xml_dir_for_minion/" \
            -output_path_page "$page_xml_dir_for_minion/" \
            -as_single_region true $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_minionextract.txt"; then
            echo "ERROR (na-pipeline.sh): MinionExtractBaselines failed. Check $tmpdir/log_minionextract.txt"
            if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionExtractBaselines finished."
    fi
fi


if [[ $HTRLOGHI -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Starting Loghi HTR process."
    page_xml_dir_htr_cut="$SRC/page" 

    if [ ! -d "$page_xml_dir_htr_cut" ] || [ -z "$(ls -A "$page_xml_dir_htr_cut"/*.xml 2>/dev/null)" ]; then
         echo "WARNING (na-pipeline.sh): Page XML directory '$page_xml_dir_htr_cut' not found or contains no XML files for MinionCut. HTR line cutting will be skipped."
    else
        echo "INFO (na-pipeline.sh): Running MinionCutFromImageBasedOnPageXMLNew..."
        if ! docker run -u "$CURRENT_UID:$CURRENT_GID" --rm \
            -v "$SRC:$SRC:rw" \
            -v "$tmpdir/imagesnippets/:$tmpdir/imagesnippets/:rw" \
            "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionCutFromImageBasedOnPageXMLNew \
            -input_path "$SRC" \
            -outputbase "$tmpdir/imagesnippets/" \
            -output_type png \
            -channels 4 \
            -threads $RECALCULATEREADINGORDERTHREADS $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_minioncut.txt"; then
            echo "ERROR (na-pipeline.sh): MinionCutFromImageBasedOnPageXMLNew failed. Check $tmpdir/log_minioncut.txt"
            if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionCutFromImageBasedOnPageXMLNew finished."
    fi 

    find "$tmpdir/imagesnippets/" -type f -name '*.png' > "$tmpdir/lines.txt"
    if [ ! -s "$tmpdir/lines.txt" ]; then
        echo "WARNING (na-pipeline.sh): No image snippets found in $tmpdir/imagesnippets/ (lines.txt is empty). HTR will not run."
    else
        LOGHIDIR_MODEL_BASE="$(dirname "${HTRLOGHIMODEL}")"
        echo "INFO (na-pipeline.sh): HTR Model Base Dir (for volume mount): $LOGHIDIR_MODEL_BASE"
        echo "INFO (na-pipeline.sh): HTR Model Path: $HTRLOGHIMODEL"

        if [ ! -f "$HTRLOGHIMODEL/charlist.txt" ] || [ ! -d "$HTRLOGHIMODEL" ]; then
             echo "ERROR (na-pipeline.sh): HTR model or charlist not found at expected paths:"
             echo "  Model Dir: $HTRLOGHIMODEL"
             echo "  Charlist: $HTRLOGHIMODEL/charlist.txt"
             if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        
        if ! docker image inspect "$DOCKERLOGHIHTR" > /dev/null 2>&1; then
            echo "WARNING (na-pipeline.sh): Docker image $DOCKERLOGHIHTR not found by inner Docker daemon. Attempting to pull..."
            docker pull "$DOCKERLOGHIHTR" || (echo "ERROR (na-pipeline.sh): Failed to pull $DOCKERLOGHIHTR" && exit 1)
        fi

        echo "INFO (na-pipeline.sh): Running Loghi HTR..."
        if ! docker run $DOCKERGPUPARAMS -u "$CURRENT_UID:$CURRENT_GID" --rm -m 32000m --shm-size 10240m \
            -v "$tmpdir:$tmpdir:rw" \
            -v "$LOGHIDIR_MODEL_BASE:$LOGHIDIR_MODEL_BASE:ro" \
            "$DOCKERLOGHIHTR" \
            bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 python3 /src/loghi-htr/src/main.py \
            --do_inference \
            --existing_model $HTRLOGHIMODEL \
            --batch_size 64 \
            --use_mask \
            --inference_list $tmpdir/lines.txt \
            --results_file $tmpdir/results.txt \
            --charlist $HTRLOGHIMODEL/charlist.txt \
            --gpu $GPU \
            --output $tmpdir/output_htr_internal/ \
            --config_file_output $tmpdir/output_htr_internal/config.json \
            --beam_width $BEAMWIDTH" 2>&1 | tee -a "$tmpdir/log_htr.txt"; then
            echo "ERROR (na-pipeline.sh): Loghi HTR failed. Check $tmpdir/log_htr.txt"
            if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): Loghi HTR finished."

        if [ ! -f "$tmpdir/results.txt" ]; then
             echo "WARNING (na-pipeline.sh): HTR results file '$tmpdir/results.txt' not found. Skipping merge."
        elif [ ! -d "$SRC/page" ]; then
             echo "WARNING (na-pipeline.sh): Page XML directory '$SRC/page' not found for merging. Skipping merge."
        else
            echo "INFO (na-pipeline.sh): Running MinionLoghiHTRMergePageXML..."
            if ! docker run -u "$CURRENT_UID:$CURRENT_GID" --rm \
                -v "$LOGHIDIR_MODEL_BASE:$LOGHIDIR_MODEL_BASE:ro" \
                -v "$SRC/page:$SRC/page:rw" \
                -v "$tmpdir:$tmpdir:ro" \
                "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionLoghiHTRMergePageXML \
                -input_path "$SRC/page" \
                -results_file "$tmpdir/results.txt" \
                -config_file "$HTRLOGHIMODEL/config.json" \
                -htr_code_config_file "$tmpdir/output_htr_internal/config.json" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_minionmerge.txt"; then
                echo "ERROR (na-pipeline.sh): MinionLoghiHTRMergePageXML failed. Check $tmpdir/log_minionmerge.txt"
                if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
            fi
            echo "INFO (na-pipeline.sh): MinionLoghiHTRMergePageXML finished."
        fi
    fi 
fi 


if [[ $RECALCULATEREADINGORDER -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Recalculating reading order."
    # --- CORRECTED: Removed 'local' keyword ---
    page_dir_recalc="$SRC/page/" 
    # --- END CORRECTION ---
    if [ ! -d "$page_dir_recalc" ] || [ -z "$(ls -A "$page_dir_recalc"/*.xml 2>/dev/null)" ]; then
        echo "WARNING (na-pipeline.sh): Page directory '$page_dir_recalc' not found or no XMLs present. Skipping reading order recalculation."
    else
        local recalc_cmd_args_array=( # 'local' is fine for this array definition
            /src/loghi-tooling/minions/target/appassembler/bin/MinionRecalculateReadingOrderNew
            -input_dir "$page_dir_recalc"
            -border_margin "$RECALCULATEREADINGORDERBORDERMARGIN"
            -threads "$RECALCULATEREADINGORDERTHREADS"
            $USE2013NAMESPACE
        )
        if [[ $RECALCULATEREADINGORDERCLEANBORDERS -eq 1 ]]; then
            recalc_cmd_args_array+=("-clean_borders")
        fi
        
        if ! docker run -u "$CURRENT_UID:$CURRENT_GID" --rm -v "$page_dir_recalc:$page_dir_recalc:rw" "$DOCKERLOGHITOOLING" "${recalc_cmd_args_array[@]}" 2>&1 | tee -a "$tmpdir/log_recalcorder.txt"; then
            echo "ERROR (na-pipeline.sh): MinionRecalculateReadingOrderNew failed. Check $tmpdir/log_recalcorder.txt"
            if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionRecalculateReadingOrderNew finished."
    fi
fi

if [[ $DETECTLANGUAGE -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Detecting language."
    # --- CORRECTED: Removed 'local' keyword ---
    page_dir_lang="$SRC/page/" 
    # --- END CORRECTION ---
     if [ ! -d "$page_dir_lang" ] || [ -z "$(ls -A "$page_dir_lang"/*.xml 2>/dev/null)" ]; then
        echo "WARNING (na-pipeline.sh): Page directory '$page_dir_lang' not found or no XMLs present. Skipping language detection."
    else
        if ! docker run -u "$CURRENT_UID:$CURRENT_GID" --rm -v "$page_dir_lang:$page_dir_lang:rw" "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionDetectLanguageOfPageXml \
            -page "$page_dir_lang" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_detectlang.txt"; then
            echo "ERROR (na-pipeline.sh): MinionDetectLanguageOfPageXml failed. Check $tmpdir/log_detectlang.txt"
            if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionDetectLanguageOfPageXml finished."
    fi
fi

if [[ $SPLITWORDS -eq 1 ]]; then
    echo "INFO (na-pipeline.sh): Splitting words (MinionSplitPageXMLTextLineIntoWords)."
    # --- CORRECTED: Removed 'local' keyword ---
    page_dir_split="$SRC/page/" 
    # --- END CORRECTION ---
    if [ ! -d "$page_dir_split" ] || [ -z "$(ls -A "$page_dir_split"/*.xml 2>/dev/null)" ]; then
        echo "WARNING (na-pipeline.sh): Page directory '$page_dir_split' not found or no XMLs present. Skipping word splitting."
    else
        if ! docker run -u "$CURRENT_UID:$CURRENT_GID" --rm -v "$page_dir_split:$page_dir_split:rw" "$DOCKERLOGHITOOLING" /src/loghi-tooling/minions/target/appassembler/bin/MinionSplitPageXMLTextLineIntoWords \
            -input_path "$page_dir_split" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log_splitwords.txt"; then
            echo "ERROR (na-pipeline.sh): MinionSplitPageXMLTextLineIntoWords failed. Check $tmpdir/log_splitwords.txt"
            if [[ $STOPONERROR -eq 1 ]]; then exit 1; fi
        fi
        echo "INFO (na-pipeline.sh): MinionSplitPageXMLTextLineIntoWords finished."
    fi
fi

echo "INFO (na-pipeline.sh): Copying results to specified output directory: $OUT"
mkdir -p "$OUT" 

echo "INFO (na-pipeline.sh): Copying original images from $SRC to $OUT"
find "$SRC" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \) -exec cp -p {} "$OUT/" \;

# --- ENHANCED: Copy generated PNGs (baselines/page images) from $SRC/page to $OUT ---
if [ -d "$SRC/page" ]; then
    echo "INFO (na-pipeline.sh): Copying XML files from $SRC/page to $OUT"
    find "$SRC/page" -maxdepth 1 -type f -name "*.xml" -exec cp -p {} "$OUT/" \;
    
    echo "INFO (na-pipeline.sh): Copying generated PNG images (baselines/page images) from $SRC/page to $OUT"
    find "$SRC/page" -maxdepth 1 -type f -name "*.png" -exec cp -p {} "$OUT/" \;
else
    echo "WARNING (na-pipeline.sh): No $SRC/page directory found to copy XMLs or PNGs from."
fi
# --- END ENHANCEMENT ---

echo "INFO (na-pipeline.sh): Cleaning up internal temporary directory: $tmpdir"
rm -rf "$tmpdir"

echo "INFO (na-pipeline.sh): na-pipeline.sh finished successfully."
