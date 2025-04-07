# Loghi Docker Wrapper

This Docker wrapper provides a containerized environment for running the Loghi Handwritten Text Recognition (HTR) pipeline. It encapsulates all necessary dependencies and tools, making it easier to deploy and use Loghi for processing historical documents.

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

## Troubleshooting

- **Docker-in-Docker issues**: Ensure the Docker socket is properly mounted
- **Permission issues**: Check permissions on mounted volumes
- **GPU not detected**: Verify NVIDIA Docker setup and GPU configuration
- **Processing errors**: Check logs in the `logs/` directory

## License

This project is licensed under the MIT License - see the LICENSE file for details. 