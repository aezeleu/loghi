# Loghi for Sittard Archive (Fork)

Loghi is a set of tools for Handwritten Text Recognition (HTR). This is a fork specifically adapted for the Sittard Archive.

This document provides an overview of the project, setup instructions, and usage guidelines, with a particular focus on the `docker-wrapper` for streamlined deployment and automated processing.

## Overview

The project includes:
* Core Loghi tools for HTR (via Git submodules).
* Scripts for running the HTR pipeline (`na-pipeline.sh`, `workspace_na_pipeline.sh`).
* A `docker-wrapper` to manage the pipeline in a Docker-in-Docker (DinD) environment with cron-based automation and GPU support.
* Configuration files and Dockerfiles for building and running the necessary components.

Two key scripts are central to the processing workflow:
* `workspace_na_pipeline.sh`: Orchestrates the processing of image directories from a defined input path, designed to be run by cron within the `loghi-wrapper` container.
* `na-pipeline.sh`: Executes the individual steps of the HTR pipeline (layout analysis, text recognition, post-processing) using Loghi's component Docker images. This script is called by `workspace_na_pipeline.sh`.

## Prerequisites

* **Docker**: Required to build and run all components. Follow [official Docker installation instructions](https://docs.docker.com/engine/install/) if not already installed.
* **NVIDIA GPU & Drivers (for GPU acceleration)**:
    * NVIDIA drivers installed on the host machine.
    * [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (nvidia-docker2) installed on the host to enable GPU access within Docker containers.
* **Git**: For cloning the repository and managing submodules.
* **Bash Shell**: For running the provided shell scripts.

## Project Setup

1.  **Clone the Repository**:
    ```bash
    # TODO: Replace with the correct Git URL for your Sittard Archive fork
    git clone git@github.com:YOUR_FORK_USERNAME/loghi-sittard.git
    cd loghi-sittard
    ```

2.  **Initialize Git Submodules**:
    The project relies on several submodules for core Loghi functionalities (`loghi-htr`, `loghi-tooling`, `laypa`, `prima-core-libs`).
    ```bash
    git submodule update --init --recursive
    ```
    These submodules will be mounted into the `loghi-wrapper` container if their paths are correctly specified in `docker-wrapper/.env`.

## Loghi Component Docker Images

The HTR pipeline uses several Docker images for its components (e.g., `loghi/docker.laypa`, `loghi/docker.htr`, `loghi/docker.loghi-tooling`).

* **Pulling from Docker Hub (Recommended for stable versions)**:
    The scripts will attempt to pull these images if they are not found locally. You can also pull them manually:
    ```bash
    docker pull loghi/docker.laypa:latest  # Or a specific version tag if available
    docker pull loghi/docker.htr:latest
    docker pull loghi/docker.loghi-tooling:latest
    ```
    *Note: `na-pipeline.sh` currently specifies version `1.3.7` for these images. Ensure your pulled or built images match the required versions or update the script accordingly.*

* **Building Component Images Locally (For development or latest code)**:
    If you want to build these images from the submodule sources:
    ```bash
    # Ensure submodules are cloned and updated
    git submodule update --init --recursive
    cd docker
    ./buildAll.sh
    cd ..
    ```
    This will build the images using the code in your local submodule directories.

## Inference Models

The HTR pipeline requires pre-trained models:
* **Laypa Model**: For layout analysis (e.g., baseline detection).
* **Loghi-HTR Model**: For handwritten text recognition.

You can download pre-trained models from the original Loghi project (link might be outdated, verify source):
[https://surfdrive.surf.nl/files/index.php/s/YA8HJuukIUKznSP](https://surfdrive.surf.nl/files/index.php/s/YA8HJuukIUKznSP)

Place the downloaded and extracted model directories in a location accessible to the pipeline. The `na-pipeline.sh` script has default paths like:
* `LAYPAMODEL="${BASEDIR}/laypa/general/baseline/config.yaml"`
* `HTRLOGHIMODEL="${BASEDIR}/loghi-htr/generic-2023-02-15"`

When using the `docker-wrapper`, these models are typically located within the mounted submodule directories (e.g., `../laypa/general/baseline/` on the host, which becomes `/app/laypa/general/baseline/` inside the container).

## Docker Wrapper for Automated Processing

The `docker-wrapper` provides an encapsulated environment for running the entire HTR pipeline. It uses Docker-in-Docker (DinD) to manage Loghi's component containers and includes a cron job for automated processing of new images.

### Docker Wrapper Features:

* **Simplified Deployment**: Runs the entire pipeline within a controlled Docker environment.
* **Docker-in-Docker (DinD)**: Manages Loghi's component Docker images.
* **Configuration via `.env`**: Pipeline behavior, paths, and cron schedule are configured using `docker-wrapper/.env`.
* **Automated Processing with Cron**: Automatically processes new image directories added to the configured workspace path.
* **GPU Support**: Leverages NVIDIA GPUs for faster processing.
* **Flexible Submodule & Model Management**: Mounts local submodule directories (containing code and models) from the host.
* **Structured Logging**: Generates detailed logs for pipeline runs.

### Docker Wrapper Setup and Usage:

1.  **Navigate to the Docker Wrapper Directory**:
    ```bash
    cd docker-wrapper
    ```

2.  **Configure the Environment**:
    * Create a `.env` file in the `docker-wrapper` directory. You can copy from `docker-wrapper/.env.example` if it exists, or create it manually.
        ```bash
        # Example: cp .env.example .env
        # Or, create .env and add the following (adjust paths and values as needed):
        ```
        **`docker-wrapper/.env` Example Content:**
        ```env
        # --- Timezone Configuration ---
        TZ=Europe/Amsterdam

        # --- Cron Schedule Configuration ---
        # Format: minute hour day-of-month month day-of-week
        # Example: "*/15 * * * *" means every 15 minutes.
        # Example: "* * * * *" runs every minute (for testing).
        CRON_SCHEDULE="*/15 * * * *"

        # --- Asset Copy Options for na-pipeline.sh (passed through workspace_na_pipeline.sh) ---
        COPY_SOURCE_IMAGES=true
        COPY_BASELINE_IMAGES=true

        # --- Behavior for workspace_na_pipeline.sh ---
        REMOVE_PROCESSED_DIRS=true # true to remove input subdirectories after successful processing
        PIPELINE_ENABLE_DEBUG_LOGGING=false # true for verbose logging from workspace_na_pipeline.sh
        PIPELINE_KEEP_TEMP_RUN_DIR=false # true to keep temp run dirs under /tmp in wrapper for debugging

        # --- Module Paths on Host (Absolute or relative to docker-compose.yml location) ---
        # These point to your Git submodules on the HOST machine.
        LAYPA_MODULE=../../laypa
        LOGHI_HTR_MODULE=../../loghi-htr
        LOGHI_TOOLING_MODULE=../../loghi-tooling
        PRIMA_CORE_LIBS_MODULE=../../prima-core-libs

        # --- Workspace and Destination Paths on Host ---
        # These are the ABSOLUTE paths on your HOST machine for input and output data.
        # Ensure these directories exist and have correct permissions.
        WORKSPACE_PATH="/mnt/archive_scans/loghi_input"
        DESTINATION_PATH="/mnt/archive_scans/loghi_output"
        ```
    * **Important**:
        * Adjust `WORKSPACE_PATH` and `DESTINATION_PATH` to **absolute paths** on your host machine.
        * Ensure the `*_MODULE` paths correctly point to your local submodule directories (relative to the `docker-wrapper` directory, or use absolute paths).

3.  **Prepare Host Directories**:
    Ensure the directories specified for `WORKSPACE_PATH`, `DESTINATION_PATH`, and the submodule paths exist on your host machine and have appropriate read/write permissions for the user running Docker.
    ```bash
    # Example based on .env settings:
    mkdir -p /mnt/archive_scans/loghi_input
    mkdir -p /mnt/archive_scans/loghi_output
    # Ensure ../../laypa, ../../loghi-htr etc. exist relative to docker-wrapper/ or adjust paths.
    ```

4.  **Build the Docker Wrapper Image**:
    A script is provided at the root of the project to build the `loghi-wrapper` image. This is necessary if you've made changes to `docker-wrapper/Dockerfile` or if the image doesn't exist.
    ```bash
    # From the project root directory (e.g., loghi-sittard/)
    ./build-docker-wrapper.sh
    ```

5.  **Start the Docker Wrapper Service**:
    From the `docker-wrapper` directory:
    ```bash
    docker-compose up -d
    ```
    This command builds the `loghi-wrapper` image if it doesn't exist (based on `docker-wrapper/Dockerfile`) and starts the service in detached mode. The container will:
    * Start an internal Docker daemon (DinD).
    * Configure and start a cron service.
    * The cron job will periodically execute `/app/workspace_na_pipeline.sh /workspace /destination` to process data.

6.  **Process Images**:
    * Place directories containing your images into the `WORKSPACE_PATH` you defined on your host. Each subdirectory within `WORKSPACE_PATH` is treated as a separate processing job.
        * Example: If `WORKSPACE_PATH` is `/mnt/archive_scans/loghi_input`, you would add folders like:
            * `/mnt/archive_scans/loghi_input/scan_batch_01/` (containing image files: .jpg, .png, .tif)
            * `/mnt/archive_scans/loghi_input/scan_batch_02/`
    * The cron job inside the `loghi-wrapper` container will detect these new directories and process them.
    * Processed output (PageXML, TXT files, and optionally images) will be saved in subdirectories within your `DESTINATION_PATH` on the host.

7.  **Monitor and View Logs**:
    * **Wrapper Container Logs (Setup, Cron Activity)**:
        ```bash
        # From the docker-wrapper directory
        docker-compose logs -f loghi-wrapper
        # Or, if you know the container name/ID:
        # docker logs -f <loghi-wrapper_container_name_or_id>
        ```
    * **Pipeline Script Logs**:
        The `workspace_na_pipeline.sh` script generates detailed logs for each run. These are stored inside the `loghi-wrapper` container in `/app/logs/run_YYYYMMDD_HHMMSS_PID/`. This `/app/logs` directory is mapped to a Docker volume named `loghi_wrapper_logs`.
        To find the host path of this volume:
        ```bash
        docker volume inspect loghi_wrapper_logs
        ```
        Navigate to the "Mountpoint" shown in the output to access the log files on your host.
    * **Cron Job Output**:
        The direct output of the cron command is logged to `/app/logs/pipeline_cron_runs.log` within the `loghi_wrapper_logs` volume.
    * **Internal Docker Daemon Logs**:
        Located at `/var/log/dockerd.log` inside the `loghi-wrapper` container. Useful for debugging DinD issues.

8.  **Stopping the Wrapper**:
    From the `docker-wrapper` directory:
    ```bash
    docker-compose down
    # To remove volumes (including logs and internal Docker storage):
    # docker-compose down -v
    ```

### Manual Pipeline Execution (for Debugging)

While the wrapper is designed for automated cron-based processing, you can manually execute the pipeline script inside the running `loghi-wrapper` container for debugging:

1.  **Ensure the wrapper is running**: `docker-compose up -d`
2.  **Place data**: Put a test directory (e.g., `my_test_batch`) with images into the `WORKSPACE_PATH` on your host. This will appear under `/workspace/my_test_batch` inside the container.
3.  **Execute the script**:
    ```bash
    docker exec <loghi-wrapper_container_name_or_id> /bin/bash /app/workspace_na_pipeline.sh /workspace /destination
    ```
    Replace `<loghi-wrapper_container_name_or_id>` with the actual name or ID of your running container (find with `docker ps`). This bypasses cron and runs the processing logic immediately.

    Alternatively, to test `na-pipeline.sh` directly on a specific set of images already copied into a temporary location within the container:
    ```bash
    # Example:
    # 1. Copy data into a temp dir inside the container, e.g., /tmp/manual_test/
    #    (This might involve docker cp or mounting another volume temporarily)
    # 2. Then exec na-pipeline.sh:
    docker exec <loghi-wrapper_container_name_or_id> /bin/bash /app/na-pipeline.sh /tmp/manual_test /tmp/manual_output true true
    ```

## Troubleshooting

* **Permissions Errors**:
    * Ensure the host directories mapped as volumes (`WORKSPACE_PATH`, `DESTINATION_PATH`, submodule paths) have correct read/write permissions for the user running Docker, or are world-writable if issues persist.
    * The `loghi-wrapper` entrypoint attempts to `chown` some internal directories to the `ubuntu` user. If you see permission errors related to `/workspace` or `/destination` inside the container, check host permissions.
* **"Docker daemon is NOT responsive" (in `na-pipeline.sh` logs)**:
    * This indicates the Docker-in-Docker daemon inside the `loghi-wrapper` container failed to start or has crashed.
    * Check the `loghi-wrapper` container logs (`docker-compose logs loghi-wrapper`) and the internal dockerd log (`/var/log/dockerd.log` inside the wrapper) for errors.
* **NVIDIA GPU Issues**:
    * Verify NVIDIA drivers are correctly installed on the host.
    * Verify NVIDIA Container Toolkit is installed and configured on the host.
    * Check `docker-compose logs loghi-wrapper` for any GPU-related errors during container startup.
    * Run `nvidia-smi` on the host to check GPU status.
* **Submodule Paths Incorrect**:
    * If using local submodules, double-check the `*_MODULE` paths in `docker-wrapper/.env`. They should be relative to the `docker-wrapper` directory (where `docker-compose.yml` is) or absolute paths on the host.
    * If submodules are not found, the pipeline might fail or use outdated/baked-in versions.
* **Script Not Executable Errors**:
    * The `workspace_na_pipeline.sh` script checks if `na-pipeline.sh` and `xml2text.sh` are executable. If you see errors like `ERROR: Script not executable: /app/na-pipeline.sh`, ensure these files have execute permissions in your Git repository (e.g., `git update-index --chmod=+x na-pipeline.sh`). These permissions should be preserved when cloned.
* **Stale Lock Files**:
    * `workspace_na_pipeline.sh` uses a lock file (`/tmp/workspace_na_pipeline.lock` inside the wrapper) to prevent multiple instances. If a run crashes, this file might remain. The script has logic to handle stale locks, but manual removal (`docker exec <container_id> rm /tmp/workspace_na_pipeline.lock`) might be needed in rare cases.
* **Cron Job Not Running**:
    * Check `docker-compose logs loghi-wrapper` for cron service startup messages.
    * Verify `CRON_SCHEDULE` in `.env` is valid.
    * Check `/app/logs/pipeline_cron_runs.log` (inside `loghi_wrapper_logs` volume) for cron execution attempts.
* **XMLStarlet Errors (in `xml2text.sh` logs)**:
    * Ensure `xmlstarlet` is correctly installed in the `loghi-wrapper` Docker image (it's included in `docker-wrapper/Dockerfile`).
    * The script tries different PAGE XML namespaces. If text extraction fails, the XML structure might not match expected formats.

## Training New Models

The script `na-pipeline-train.sh` is provided for training new models. Detailed instructions for training are beyond the scope of this quick start guide and depend on the specific Loghi training procedures. Consult the original Loghi documentation or specific training guides.

## Further Customization

* **Pipeline Steps**: Modify `na-pipeline.sh` to change models, parameters, or enable/disable specific processing steps (Laypa, HTR, post-processing minions).
* **Docker Images**: Update component Dockerfiles in the `docker/` directory or the `docker-wrapper/Dockerfile` for custom dependencies or versions.
* **Cron Behavior**: Adjust `CRON_SCHEDULE` in `docker-wrapper/.env` or modify `workspace_na_pipeline.sh` for more complex scheduling logic.

## Author / Maintainer

This "Loghi-Aezel" fork is developed and maintained by:

* **Arthur Rahimov**
    * Email: a.ragimov@aezel.eu
    * Organization: [Aezel](https://aezel.eu)
    * Personal Website: [ragmon.nl](https://ragmon.nl)