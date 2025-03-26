#!/bin/bash
VERSION=1.3.7
set -e

# Check if source directory is accessible
check_source_directory() {
    local src_path="$1"
    if [ ! -d "$src_path" ]; then
        echo "Error: Source directory '$src_path' does not exist or is not accessible"
        exit 1
    fi

    # Try to list directory contents to verify read permissions
    if ! ls "$src_path" >/dev/null 2>&1; then
        echo "Error: Cannot access contents of source directory '$src_path'"
        echo "Please check if the directory is properly mounted and has correct permissions"
        echo "For Google Drive/Workspace, ensure the drive is properly mounted in WSL"
        exit 1
    fi
}

# Stop on error, if set to 1 will exit program if any of the docker commands fail
STOPONERROR=1

# set to 1 if you want to enable, 0 otherwise, select just one
BASELINELAYPA=1

# # Set the base directory to the project directory
if [ -z "$BASEDIR" ]; then
    BASEDIR=/home/default/Companies/Archive/loghi-main # works for Arthur
fi

#
#LAYPAMODEL=/home/rutger/src/laypa-models/general/baseline/config.yaml
#LAYPAMODELWEIGHTS=/home/rutger/src/laypa-models/general/baseline/model_best_mIoU.pth

# LAYPAMODEL=INSERT_FULL_PATH_TO_YAML_HERE
LAYPAMODEL=$BASEDIR/laypa/general/baseline/config.yaml
# LAYPAMODEL=/home/default/loghi-main/laypa/general/baseline/config.yaml

# LAYPAMODELWEIGHTS=INSERT_FULLPATH_TO_PTH_HERE
LAYPAMODELWEIGHTS=$BASEDIR/laypa/general/baseline/model_best_mIoU.pth

# set to 1 if you want to enable, 0 otherwise, select just one
HTRLOGHI=1

#HTRLOGHIMODEL=/home/rutger/src/loghi-htr-models/republic-2023-01-02-base-generic_new14-2022-12-20-valcer-0.0062
HTRLOGHIMODEL=$BASEDIR/loghi-htr/generic-2023-02-15

# set this to 1 for recalculating reading order, line clustering and cleaning.
RECALCULATEREADINGORDER=1
# if the edge of baseline is closer than x pixels...
RECALCULATEREADINGORDERBORDERMARGIN=50
# clean if 1
RECALCULATEREADINGORDERCLEANBORDERS=0
# how many threads to use
RECALCULATEREADINGORDERTHREADS=4

#detect language of pagexml, set to 1 to enable, disable otherwise
DETECTLANGUAGE=1
#interpolate word locations
SPLITWORDS=1
#BEAMWIDTH: higher makes results slightly better at the expense of lot of computation time. In general don't set higher than 10
BEAMWIDTH=1
#used gpu ids, set to "-1" to use CPU, "0" for first, "1" for second, etc
GPU=0

DOCKERLOGHITOOLING=loghi/docker.loghi-tooling:$VERSION
DOCKERLAYPA=loghi/docker.laypa:$VERSION
DOCKERLOGHIHTR=loghi/docker.htr:$VERSION
USE2013NAMESPACE=" -use_2013_namespace "

# DO NO EDIT BELOW THIS LINE
if [ -z $1 ]; then echo "please provide path to images to be HTR-ed" && exit 1; fi;
if [ -z $2 ]; then echo "please provide path to result directory" && exit 1; fi;

# Check source directory before proceeding
check_source_directory "$1"

tmpdir=$(mktemp -d)
echo $tmpdir

DOCKERGPUPARAMS=""
if [[ $GPU -gt -1 ]]; then
        DOCKERGPUPARAMS="--gpus device=${GPU}"
        echo "using GPU ${GPU}"
fi

SRC=`realpath $1`
OUT=`realpath $2`
echo OUT: ${OUT}
# exit;

mkdir $tmpdir/imagesnippets/
mkdir $tmpdir/linedetection
mkdir $tmpdir/output


find $SRC -name '*.done' -exec rm -f "{}" \;


if [[ $BASELINELAYPA -eq 1 ]]
then
        echo "starting Laypa baseline detection"

        input_dir=$SRC
        output_dir=$SRC
        LAYPADIR="$(dirname "${LAYPAMODEL}")"

        if [[ ! -d $input_dir ]]; then
                echo "Specified input dir (${input_dir}) does not exist, stopping program"
                exit 1
        fi

        if [[ ! -d $output_dir ]]; then
                echo "Could not find output dir (${output_dir}), creating one at specified location"
                mkdir -p $output_dir
        fi

        echo "Running Laypa baseline detection..."
        if ! docker run $DOCKERGPUPARAMS --rm -u $(id -u ${USER}):$(id -g ${USER}) -m 32000m --shm-size 10240m \
            -v "$LAYPADIR:$LAYPADIR" \
            -v "$input_dir:$input_dir" \
            -v "$output_dir:$output_dir" \
            $DOCKERLAYPA \
            python run.py \
            -c "$LAYPAMODEL" \
            -i "$input_dir" \
            -o "$output_dir" \
            --opts MODEL.WEIGHTS "" TEST.WEIGHTS "$LAYPAMODELWEIGHTS" 2>&1 | tee -a "$tmpdir/log.txt"; then
            echo "Error: Laypa baseline detection failed"
            exit 1
        fi

        echo "Running MinionExtractBaselines..."
        if ! docker run --rm -u $(id -u ${USER}):$(id -g ${USER}) \
            -v "$output_dir:$output_dir" \
            $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionExtractBaselines \
            -input_path_png "$output_dir/page/" \
            -input_path_page "$output_dir/page/" \
            -output_path_page "$output_dir/page/" \
            -as_single_region true $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log.txt"; then
            echo "Error: MinionExtractBaselines failed"
            exit 1
        fi
fi

# #HTR option 1 LoghiHTR
if [[ $HTRLOGHI -eq 1 ]]
then
        echo "starting Loghi HTR"
        
        echo "Running MinionCutFromImageBasedOnPageXMLNew..."
        if ! docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm \
            -v "$SRC:$SRC" \
            -v "$tmpdir:$tmpdir" \
            $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionCutFromImageBasedOnPageXMLNew \
            -input_path "$SRC" \
            -outputbase "$tmpdir/imagesnippets/" \
            -output_type png \
            -channels 4 \
            -threads 4 $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log.txt"; then
            echo "Error: MinionCutFromImageBasedOnPageXMLNew failed"
            exit 1
        fi

        find "$tmpdir/imagesnippets/" -type f -name '*.png' > "$tmpdir/lines.txt"

        LOGHIDIR="$(dirname "${HTRLOGHIMODEL}")"
        
        echo "Running Loghi HTR..."
        if ! docker run $DOCKERGPUPARAMS -u $(id -u ${USER}):$(id -g ${USER}) --rm -m 32000m --shm-size 10240m \
            -v /tmp:/tmp \
            -v "$tmpdir:$tmpdir" \
            -v "$LOGHIDIR:$LOGHIDIR" \
            $DOCKERLOGHIHTR \
            bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 python3 /src/loghi-htr/src/main.py \
            --do_inference \
            --existing_model $HTRLOGHIMODEL \
            --batch_size 64 \
            --use_mask \
            --inference_list $tmpdir/lines.txt \
            --results_file $tmpdir/results.txt \
            --charlist $HTRLOGHIMODEL/charlist.txt \
            --gpu $GPU \
            --output $tmpdir/output/ \
            --config_file_output $tmpdir/output/config.json \
            --beam_width $BEAMWIDTH" 2>&1 | tee -a "$tmpdir/log.txt"; then
            echo "Error: Loghi HTR failed"
            exit 1
        fi

        echo "Running MinionLoghiHTRMergePageXML..."
        if ! docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm \
            -v "$LOGHIDIR:$LOGHIDIR" \
            -v "$SRC:$SRC" \
            -v "$tmpdir:$tmpdir" \
            $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionLoghiHTRMergePageXML \
            -input_path "$SRC/page" \
            -results_file "$tmpdir/results.txt" \
            -config_file "$HTRLOGHIMODEL/config.json" \
            -htr_code_config_file "$tmpdir/output/config.json" $USE2013NAMESPACE 2>&1 | tee -a "$tmpdir/log.txt"; then
            echo "Error: MinionLoghiHTRMergePageXML failed"
            exit 1
        fi
fi

if [[ $RECALCULATEREADINGORDER -eq 1 ]]
then
        echo "recalculating reading order"
        if [[ $RECALCULATEREADINGORDERCLEANBORDERS -eq 1 ]]
        then
                echo "and cleaning"
                docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm -v $SRC/:$SRC/ -v $tmpdir:$tmpdir $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionRecalculateReadingOrderNew \
                        -input_dir $SRC/page/ \
			-border_margin $RECALCULATEREADINGORDERBORDERMARGIN \
			-clean_borders \
			-threads $RECALCULATEREADINGORDERTHREADS $USE2013NAMESPACE | tee -a $tmpdir/log.txt

                if [[ $STOPONERROR && $? -ne 0 ]]; then
                        echo "MinionRecalculateReadingOrderNew has errored, stopping program"
                        exit 1
                fi
        else
                docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm -v $SRC/:$SRC/ -v $tmpdir:$tmpdir $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionRecalculateReadingOrderNew \
                        -input_dir $SRC/page/ \
			-border_margin $RECALCULATEREADINGORDERBORDERMARGIN \
			-threads $RECALCULATEREADINGORDERTHREADS $USE2013NAMESPACE| tee -a $tmpdir/log.txt

                if [[ $STOPONERROR && $? -ne 0 ]]; then
                        echo "MinionRecalculateReadingOrderNew has errored, stopping program"
                        exit 1
                fi
        fi
fi
if [[ $DETECTLANGUAGE -eq 1 ]]
then
        echo "detecting language..."
        docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm -v $SRC/:$SRC/ -v $tmpdir:$tmpdir $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionDetectLanguageOfPageXml \
                -page $SRC/page/ $USE2013NAMESPACE | tee -a $tmpdir/log.txt


        if [[ $STOPONERROR && $? -ne 0 ]]; then
                echo "MinionDetectLanguageOfPageXml has errored, stopping program"
                exit 1
        fi
fi


if [[ $SPLITWORDS -eq 1 ]]
then
        echo "MinionSplitPageXMLTextLineIntoWords..."
        docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm -v $SRC/:$SRC/ -v $tmpdir:$tmpdir $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionSplitPageXMLTextLineIntoWords \
                -input_path $SRC/page/ $USE2013NAMESPACE | tee -a $tmpdir/log.txt

        if [[ $STOPONERROR && $? -ne 0 ]]; then
                echo "MinionSplitPageXMLTextLineIntoWords has errored, stopping program"
                exit 1
        fi
fi

# cleanup results
rm -rf $tmpdir

# make output dir and copy required files
mkdir -p "$OUT/"

# Copy source images (assuming common image extensions)
find "$SRC" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tif" -o -iname "*.tiff" \) -exec cp {} "$OUT/" \;

# Copy XML files from page directory, excluding baseline images
find "$SRC/page" -type f -name "*.xml" -exec cp {} "$OUT/" \;


