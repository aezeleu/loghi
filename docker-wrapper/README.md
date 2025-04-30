# Loghi Docker Wrapper

This Docker wrapper provides a containerized environment for running the Loghi HTR processing pipeline.

## Configuration

### Environment Variables

Create a `.env` file in the docker-wrapper directory (copy from `.env-example`):

```bash
cp .env-example .env
```

Edit the `.env` file to set your specific paths:

```bash
# Google Drive paths configuration
INPUT_SOURCE_PATH=/path/to/your/input/directory
OUTPUT_DEST_PATH=/path/to/your/output/directory

# Other environment variables
TZ=Europe/Amsterdam
ENABLE_CRON=true
USE_GIT_SUBMODULES=false
```

#### Required Variables

- `INPUT_SOURCE_PATH`: Path to your Google Drive input directory in WSL
- `OUTPUT_DEST_PATH`: Path to your Google Drive output directory in WSL

#### Optional Variables

- `TZ`: Timezone (default: Europe/Amsterdam)
- `ENABLE_CRON`: Enable/disable CRON scheduling (default: true)
- `USE_GIT_SUBMODULES`: Enable/disable Git submodules (default: false)

### Google Drive Setup

1. Mount your Google Drive in WSL
2. Set the correct paths in your `.env` file
3. Ensure the paths are accessible and have proper permissions

Example paths for different Google Drive accounts:
```bash
# Account 1
INPUT_SOURCE_PATH=/mnt/i/Shared drives/Loghi/input
OUTPUT_DEST_PATH=/mnt/i/Shared drives/Loghi/output

# Account 2
INPUT_SOURCE_PATH=/mnt/g/Other Drive/Loghi/input
OUTPUT_DEST_PATH=/mnt/g/Other Drive/Loghi/output
```

## Usage

1. Configure your environment:
```bash
cd docker-wrapper
cp .env-example .env
# Edit .env with your paths
```

2. Build and start the container:
```bash
docker-compose up -d --build
```

3. Monitor the logs:
```bash
docker-compose logs -f
```

The container will:
- Mount your specified Google Drive directories
- Process files from the input directory every 5 minutes
- Save results to the output directory
- Log activities to the local logs directory

## Troubleshooting

### Common Issues

1. **Permission Issues**
   - Ensure the mounted directories have proper permissions
   - The container runs as root to handle permissions

2. **Path Issues**
   - Verify your Google Drive paths are correct
   - Check that the paths are properly mounted in WSL
   - Ensure paths in .env match your actual directory structure

3. **CRON Issues**
   - Check /app/logs/cron.log for CRON-related errors
   - Verify the CRON service is running in the container

## GPU Support

The container is configured to use NVIDIA GPUs if available. To enable GPU support:

1. Install NVIDIA Docker runtime
2. The container will automatically detect and use available GPUs

## Maintenance

- Logs are stored in the `logs` directory
- Configuration files are in the `config` directory
- Models are stored in the `models` directory

## Features

- Complete Docker environment for local deployment
- Docker-in-Docker capability to run Loghi's component containers
- Configurable through environment variables and mounted configuration files
- CRON job support for automated processing
- Two options for Git submodules: mount from host or pull directly
- GPU support for faster processing (requires NVIDIA Docker setup)

## Requirements

- Docker and Docker Compose
- Git (if using Git submodules)
- Docker with GPU support (optional, for GPU acceleration)

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/loghi-docker.git
   cd loghi-docker
   ```

2. Configure the environment:
   ```bash
   # Copy and edit the configuration file
   mkdir -p config
   cp config/loghi.conf.default config/loghi.conf
   # Edit the config/loghi.conf file as needed
   ```

3. Prepare directories:
   ```bash
   mkdir -p data/input data/output logs models
   ```

4. Start the container:
   ```bash
   docker-compose up -d
   ```

## Configuration

### Environment Variables

The following environment variables can be set in the `docker-compose.yml` file:

- `TZ`: Timezone (default: Europe/Amsterdam)
- `ENABLE_CRON`: Enable CRON jobs (true/false, default: false)
- `USE_GIT_SUBMODULES`: Use Git submodules instead of mounted volumes (true/false, default: false)

### Configuration Files

The main configuration file is `config/loghi.conf`, which contains settings for:

- Docker image versions
- Model paths
- Feature flags
- Performance settings
- CRON schedule
- Docker settings

### CRON Jobs

To enable automated processing with CRON:

1. Set `ENABLE_CRON=true` in the environment variables
2. Edit the CRON schedule in `config/loghi.conf` or customize the `config/crontab` file

## Directory Structure

- `config/`: Configuration files
- `data/input/`: Input directory for images to process
- `data/output/`: Output directory for processed files
- `logs/`: Log files
- `models/`: Model files (if using downloaded models)
- `modules/`: Git submodules (if mounted from host)

## Usage

### Run the Pipeline Directly

```bash
docker exec loghi-wrapper run-pipeline /app/data/input /app/data/output
```

### Run Batch Processing

```bash
docker exec loghi-wrapper run-batch /app/data/input /app/data/output
```

### Generate Synthetic Images

```bash
docker exec loghi-wrapper generate-images --output /app/data/output/synthetic
```

### Train a New Model

```bash
docker exec loghi-wrapper train
```

### Show Help

```bash
docker exec loghi-wrapper help
```

## Git Submodules

You can use the Loghi Git submodules in two ways:

1. **Mount from host** (default):
   - Set `USE_GIT_SUBMODULES=false` in environment variables
   - Ensure the submodules are cloned and available on the host
   - Mount the submodule directories in the `docker-compose.yml` file

2. **Pull within container**:
   - Set `USE_GIT_SUBMODULES=true` in environment variables
   - The container will automatically clone and initialize the submodules

## GPU Support

To enable GPU support:

1. Ensure you have NVIDIA Docker installed
2. Uncomment the GPU section in the `docker-compose.yml` file
3. Set `GPU=0` (or another GPU index) in your `config/loghi.conf` file

## License

This project is licensed under the MIT License - see the LICENSE file for details. 