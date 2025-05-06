#!/bin/bash
set -e

# Function to handle container shutdown
cleanup() {
    echo "Stopping services..."
    if [ -f /var/run/crond.pid ]; then
        kill $(cat /var/run/crond.pid)
    fi
    exit 0
}

# Set trap for graceful shutdown
trap cleanup SIGTERM SIGINT

# Create necessary directories (only those that need to be writable)
mkdir -p /app/temp_workspace /app/logs /app/config_rw
chmod -R 777 /app/temp_workspace /app/logs /app/config_rw

# Check if Docker socket is available
if [ ! -S /var/run/docker.sock ]; then
    echo "WARNING: Docker socket (/var/run/docker.sock) not found."
    echo "Docker-in-Docker functionality will not be available."
    echo "Please mount the Docker socket from the host when running this container."
fi

# Set timezone if provided
if [ ! -z "$TZ" ]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
fi

# Copy config files to writable location
echo "Copying configuration files to writable location..."
cp -r /app/config/* /app/config_rw/
export LOGHI_CONFIG_DIR=/app/config_rw

# Initialize configuration files if they don't exist
if [ ! -f $LOGHI_CONFIG_DIR/loghi.conf ]; then
    echo "Initializing configuration files..."
    cp /app/config/loghi.conf.default $LOGHI_CONFIG_DIR/loghi.conf
fi

# Check if we're using git submodules or mounted modules
if [ "$USE_GIT_SUBMODULES" = "true" ]; then
    echo "Using Git submodules..."
    cd /app
    git init
    cp /app/config/.gitmodules.default /app/.gitmodules
    git submodule update --init --recursive
else
    echo "Using mounted modules..."
fi

# Update BASEDIR in configuration
sed -i "s|BASEDIR=.*|BASEDIR=/app|g" $LOGHI_CONFIG_DIR/loghi.conf

# Patch pipeline scripts for Docker wrapper compatibility
/app/scripts/patch-pipeline.sh

# Update scripts with configuration values
/app/scripts/update-scripts.sh

# Handle different commands
case "$1" in
    start)
        echo "Starting cron service..."
        # Start cron in foreground mode
        cron -f &
        CRON_PID=$!
        echo $CRON_PID > /var/run/crond.pid
        echo "Loghi container started. Running in daemon mode."
        # Keep container running and wait for cron
        wait $CRON_PID
        ;;
    run-pipeline)
        echo "Running Loghi pipeline for input directory: $2"
        if [ ! -d "$2" ]; then
            echo "Error: Input directory $2 does not exist"
            exit 1
        fi
        /app/pipeline_wrapper.sh "$2" "$3"
        ;;
    run-batch)
        echo "Running Loghi batch processing for workspace: $2"
        if [ ! -d "$2" ]; then
            echo "Error: Input directory $2 does not exist"
            exit 1
        fi
        /app/workspace_na_pipeline.sh "$2"
        ;;
    generate-images)
        echo "Generating synthetic images"
        /app/generate-images.sh "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
        ;;
    train)
        echo "Training new model"
        /app/na-pipeline-train.sh
        ;;
    create-data)
        echo "Creating training data"
        /app/create_train_data.sh "$2" "$3"
        ;;
    help)
        echo "Loghi Docker Wrapper - Available commands:"
        echo "  start                   - Start container in daemon mode"
        echo "  run-pipeline [input] [output] - Run pipeline on specified input directory"
        echo "  run-batch [input] [output]    - Run batch processing on workspace"
        echo "  generate-images [options]     - Generate synthetic images"
        echo "  train                   - Train a new model"
        echo "  create-data [input] [output]  - Create training data"
        echo "  help                    - Show this help message"
        ;;
    *)
        echo "Usage: $0 {start|run-pipeline|run-batch}"
        exit 1
        ;;
esac 