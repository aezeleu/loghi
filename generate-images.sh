#!/bin/bash

# Configuration
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
DEFAULT_FONTS_DIR="${SCRIPT_DIR}/fonts"
DEFAULT_TEXT_DIR="${SCRIPT_DIR}/text"
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/output"
MAX_FILES=10
IMAGE_QUALITY=300  # DPI
BACKGROUND_COLOR="white"
TEXT_COLOR="black"
FONT_SIZE=12
NOISE_LEVEL=0.1  # Salt and pepper noise level

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Docker is running
check_docker() {
    if ! command_exists docker; then
        echo "Error: Docker is not installed"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker daemon is not running"
        exit 1
    fi
}

# Function to check if required directories exist
check_directories() {
    local fonts_dir="$1"
    local text_dir="$2"
    local output_dir="$3"
    
    if [ ! -d "$fonts_dir" ]; then
        echo "Error: Fonts directory does not exist: $fonts_dir"
        exit 1
    fi
    
    if [ ! -d "$text_dir" ]; then
        echo "Error: Text directory does not exist: $text_dir"
        exit 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
}

# Function to get absolute path
get_abs_path() {
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# Parse command line arguments
FONTS_DIR="$DEFAULT_FONTS_DIR"
TEXT_DIR="$DEFAULT_TEXT_DIR"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

while [[ $# -gt 0 ]]; do
    case $1 in
        --fonts)
            FONTS_DIR="$2"
            shift 2
            ;;
        --text)
            TEXT_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --max-files)
            MAX_FILES="$2"
            shift 2
            ;;
        --quality)
            IMAGE_QUALITY="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --fonts <dir>     Fonts directory (default: $DEFAULT_FONTS_DIR)"
            echo "  --text <dir>      Text directory (default: $DEFAULT_TEXT_DIR)"
            echo "  --output <dir>    Output directory (default: $DEFAULT_OUTPUT_DIR)"
            echo "  --max-files <n>   Maximum number of files to generate (default: $MAX_FILES)"
            echo "  --quality <dpi>   Image quality in DPI (default: $IMAGE_QUALITY)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Convert paths to absolute paths
FONTS_DIR="$(get_abs_path "$FONTS_DIR")"
TEXT_DIR="$(get_abs_path "$TEXT_DIR")"
OUTPUT_DIR="$(get_abs_path "$OUTPUT_DIR")"

# Check prerequisites
check_docker
check_directories "$FONTS_DIR" "$TEXT_DIR" "$OUTPUT_DIR"

# Pull the Docker image if not present
if ! docker image inspect loghi/docker.loghi-tooling >/dev/null 2>&1; then
    echo "Pulling loghi/docker.loghi-tooling image..."
    docker pull loghi/docker.loghi-tooling
fi

# Run the image generation
echo "Generating images with the following configuration:"
echo "Fonts directory: $FONTS_DIR"
echo "Text directory: $TEXT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Max files: $MAX_FILES"
echo "Image quality: ${IMAGE_QUALITY} DPI"

docker run -ti \
    -v "$FONTS_DIR:$FONTS_DIR" \
    -v "$TEXT_DIR:$TEXT_DIR" \
    -v "$OUTPUT_DIR:$OUTPUT_DIR" \
    loghi/docker.loghi-tooling \
    /src/loghi-tooling/minions/target/appassembler/bin/MinionGeneratePageImages \
    -add_salt_and_pepper \
    -font_path "$FONTS_DIR" \
    -text_path "$TEXT_DIR" \
    -output_path "$OUTPUT_DIR" \
    -max_files "$MAX_FILES" \
    -dpi "$IMAGE_QUALITY" \
    -background_color "$BACKGROUND_COLOR" \
    -text_color "$TEXT_COLOR" \
    -font_size "$FONT_SIZE" \
    -noise_level "$NOISE_LEVEL"

# Check if generation was successful
if [ $? -eq 0 ]; then
    echo "Image generation completed successfully"
    echo "Generated files are in: $OUTPUT_DIR"
else
    echo "Error: Image generation failed"
    exit 1
fi
