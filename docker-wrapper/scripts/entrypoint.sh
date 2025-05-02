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
    # Initialize and update git submodules
    cd /app
    git init
    cp /app/config/.gitmodules.default /app/.gitmodules
    git submodule update --init --recursive
    
    # Set the proper paths in the configuration
    sed -i "s|LAYPAMODEL=.*|LAYPAMODEL=/app/laypa/general/baseline/config.yaml|g" $LOGHI_CONFIG_DIR/loghi.conf
    sed -i "s|LAYPAMODELWEIGHTS=.*|LAYPAMODELWEIGHTS=/app/laypa/general/baseline/model_best_mIoU.pth|g" $LOGHI_CONFIG_DIR/loghi.conf
    sed -i "s|HTRLOGHIMODEL=.*|HTRLOGHIMODEL=/app/loghi-htr/generic-2023-02-15|g" $LOGHI_CONFIG_DIR/loghi.conf
else
    echo "Using mounted modules..."
    
    # Update configuration to use mounted modules
    sed -i "s|LAYPAMODEL=.*|LAYPAMODEL=$LOGHI_MODULES_DIR/laypa/general/baseline/config.yaml|g" $LOGHI_CONFIG_DIR/loghi.conf
    sed -i "s|LAYPAMODELWEIGHTS=.*|LAYPAMODELWEIGHTS=$LOGHI_MODULES_DIR/laypa/general/baseline/model_best_mIoU.pth|g" $LOGHI_CONFIG_DIR/loghi.conf
    sed -i "s|HTRLOGHIMODEL=.*|HTRLOGHIMODEL=$LOGHI_MODULES_DIR/loghi-htr/generic-2023-02-15|g" $LOGHI_CONFIG_DIR/loghi.conf
fi

# Update BASEDIR in configuration
sed -i "s|BASEDIR=.*|BASEDIR=/app|g" $LOGHI_CONFIG_DIR/loghi.conf

# Patch pipeline scripts for Docker wrapper compatibility
/app/scripts/patch-pipeline.sh

# Update scripts with configuration values
/app/scripts/update-scripts.sh

# Start cron if enabled
if [ "$ENABLE_CRON" = "true" ]; then
    echo "Starting cron service..."
    cron -f &
    echo $! > /var/run/crond.pid
fi

# Handle different commands
case "$1" in
    start)
        echo "Loghi container started. Running in daemon mode."
        # Keep container running
        exec tail -f /dev/null
        ;;
    run-pipeline)
        echo "Running Loghi pipeline for input directory: $2"
        # Ensure input directory exists and is accessible
        if [ ! -d "$2" ]; then
            echo "Error: Input directory $2 does not exist"
            exit 1
        fi
        /app/pipeline_wrapper.sh "$2" "$3"
        ;;
    run-batch)
        echo "Running Loghi batch processing for workspace: $2"
        # Ensure input directory exists and is accessible
        if [ ! -d "$2" ]; then
            echo "Error: Input directory $2 does not exist"
            exit 1
        fi
        # Create temporary workspace
        mkdir -p /app/temp_workspace
        /app/workspace_na_pipeline.sh "$2" "$3"
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
        exec "$@"
        ;;
esac 