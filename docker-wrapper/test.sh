#!/bin/bash
set -e

# Load environment variables if .env file exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    # Use a more robust way to load environment variables
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line =~ ^#.*$ ]] && continue
        [[ -z $line ]] && continue
        
        # Handle paths with spaces
        if [[ $line =~ ^(INPUT_SOURCE_PATH|OUTPUT_DEST_PATH)= ]]; then
            # Extract the variable name and value
            var_name="${line%%=*}"
            var_value="${line#*=}"
            # Export the variable with proper quoting
            export "$var_name"="$var_value"
        else
            # For other variables, use standard export
            export "$line"
        fi
    done < .env
fi

# Function to display help
show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  build     - Build the Docker image"
    echo "  start     - Start the container"
    echo "  stop      - Stop the container"
    echo "  logs      - Show container logs"
    echo "  run       - Run a command in the container"
    echo "  test      - Run a test pipeline"
    echo "  clean     - Clean up volumes and containers"
    echo "  help      - Show this help message"
}

# Function to build the image
build_image() {
    echo "Building Docker image..."
    docker compose build
}

# Function to start the container
start_container() {
    echo "Starting container..."
    docker compose up -d
}

# Function to stop the container
stop_container() {
    echo "Stopping container..."
    docker compose down
}

# Function to show logs
show_logs() {
    echo "Showing container logs..."
    docker compose logs -f
}

# Function to run a command
run_command() {
    echo "Running command in container..."
    docker compose run --rm loghi-wrapper "$@"
}

# Function to run a test
run_test() {
    echo "Running test pipeline..."
    
    # Create temporary test directories if they don't exist
    local test_input_dir="${INPUT_SOURCE_PATH:-./data/input}/test"
    local test_output_dir="${OUTPUT_DEST_PATH:-./data/output}"
    
    mkdir -p "$test_input_dir"
    echo "Test content" > "$test_input_dir/test.txt"
    
    # Run the pipeline
    docker compose run --rm loghi-wrapper run-batch /app/data/input/test /app/data/output
    
    # Check if output was created
    if [ -d "$test_output_dir" ]; then
        echo "Test completed successfully!"
        echo "Output directory: $test_output_dir"
    else
        echo "Test failed - no output directory created"
    fi
}

# Function to clean up
cleanup() {
    echo "Cleaning up..."
    docker compose down -v
    docker volume rm loghi_temp_workspace 2>/dev/null || true
}

# Main script
case "$1" in
    build)
        build_image
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    logs)
        show_logs
        ;;
    run)
        shift
        run_command "$@"
        ;;
    test)
        run_test
        ;;
    clean)
        cleanup
        ;;
    help|*)
        show_help
        ;;
esac 