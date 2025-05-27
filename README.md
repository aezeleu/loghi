# Loghi-Aezel (Fork of Loghi)

Loghi is a set of tools for Handwritten Text Recognition (HTR). This "Loghi-Aezel" fork is specifically adapted for the Sittard Archive, Limburg province. It is based on the original [Loghi project by KNAW Huc](https://github.com/knaw-huc/loghi).

This document provides an overview of the `docker-wrapper` for the Loghi-Aezel project, detailing its setup, usage, and configuration for streamlined deployment and automated processing.

## Overview of the Docker Wrapper

The `docker-wrapper` component of Loghi-Aezel aims to simplify the deployment and operation of the HTR pipeline. It includes:
* Core Loghi tools for HTR (via Git submodules, managed by the main project).
* Scripts for running the HTR pipeline (`na-pipeline.sh`, `workspace_na_pipeline.sh` - located in the main project directory).
* A dedicated Docker environment (`docker-wrapper`) to manage the pipeline in a Docker-in-Docker (DinD) setup.
* Cron-based automation for processing image directories.
* Support for NVIDIA GPU acceleration.
* Configuration files and a `Dockerfile` for building and running the wrapper.

Two key scripts from the main project are central to the processing workflow orchestrated by this wrapper:
* `workspace_na_pipeline.sh`: Orchestrates the processing of image directories from a defined input path, designed to be run by cron within the `loghi-wrapper` container.
* `na-pipeline.sh`: Executes the individual steps of the HTR pipeline (layout analysis, text recognition, post-processing) using Loghi's component Docker images. This script is called by `workspace_na_pipeline.sh`.

## Prerequisites

* **Docker**: Required to build and run all components. Follow [official Docker installation instructions](https://docs.docker.com/engine/install/) if not already installed.
* **NVIDIA GPU & Drivers (for GPU acceleration)**:
    * NVIDIA drivers installed on the host machine.
    * [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (nvidia-docker2) installed on the host to enable GPU access within Docker containers.
* **Git**: For cloning the main Loghi-Aezel repository and its submodules.
* **Bash Shell**: For running utility shell scripts.

## Project Setup (Main Loghi-Aezel Repository)

Before using the `docker-wrapper`, ensure the main Loghi-Aezel project is set up:

1.  **Clone the Repository**:
    ```bash
    # Replace with the correct Git URL for your Loghi-Aezel fork
    git clone git@github.com:YOUR_USERNAME/loghi-aezel.git
    cd loghi-aezel
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
    docker pull loghi/docker.laypa:latest  # Or a specific version tag like 1.3.7
    docker pull loghi/docker.htr:latest
    docker pull loghi/docker.loghi-tooling:latest
    ```
    *Note: `na-pipeline.sh` (in the main project) currently specifies version `1.3.7` for these images. Ensure your pulled or built images match the required versions or update the script accordingly.*

* **Building Component Images Locally (For development or latest code)**:
    If you want to build these images from the submodule sources (from the root of the `loghi-aezel` project):
    ```bash
    # Ensure submodules are cloned and updated
    git submodule update --init --recursive
    cd docker # This 'docker' directory is in the root of loghi-aezel, not docker-wrapper
    ./buildAll.sh
    cd ..
    ```
    This will build the images using the code in your local submodule directories.

## Inference Models

The HTR pipeline requires pre-trained models:
* **Laypa Model**: For layout analysis (e.g., baseline detection).
* **Loghi-HTR Model**: For handwritten text recognition.

You can download pre-trained models from the original Loghi project (verify link validity):
[https://surfdrive.surf.nl/files/index.php/s/YA8HJuukIUKznSP](https://surfdrive.surf.nl/files/index.php/s/YA8HJuukIUKznSP)

Place the downloaded and extracted model directories in a location accessible to the pipeline. The `na-pipeline.sh` script has default paths like:
* `LAYPAMODEL="${BASEDIR}/laypa/general/baseline/config.yaml"`
* `HTRLOGHIMODEL="${BASEDIR}/loghi-htr/generic-2023-02-15"`

When using the `docker-wrapper`, these models are typically located within the mounted submodule directories (e.g., `../laypa/general/baseline/` on the host, relative to `docker-wrapper/`, which becomes `/app/laypa/general/baseline/` inside the container).

## Docker Wrapper for Automated Processing

The `docker-wrapper` provides an encapsulated environment for running the entire HTR pipeline.

### Docker Wrapper Features:

* **Simplified Deployment**: Runs the entire pipeline within a controlled Docker environment.
* **Docker-in-Docker (DinD)**: Manages Loghi's component Docker images.
* **Configuration via `.env`**: Pipeline behavior, paths, and cron schedule are configured using `docker-wrapper/.env`.
* **Automated Processing with Cron**: Automatically processes new image directories added to the configured workspace path (if `ENABLE_CRON=true`).
* **GPU Support**: Leverages NVIDIA GPUs for faster processing.
* **Flexible Submodule & Model Management**: Mounts local submodule directories (containing code and models) from the host.
* **Structured Logging**: Generates detailed logs for pipeline runs.

### Docker Wrapper Setup and Usage:

1.  **Navigate to the Docker Wrapper Directory** (within your cloned `loghi-aezel` project):
    ```bash
    cd docker-wrapper
    ```

2.  **Configure the Environment**:
    * Create a `.env` file in the `docker-wrapper` directory. You can copy from an example if one is provided, or create it manually.
        **`docker-wrapper/.env` Example Content:**
        ```env
        # --- Timezone Configuration ---
        TZ=Europe/Amsterdam

        # --- Cron Service Control ---
        ENABLE_CRON=true # Set to false to disable cron job setup

        # --- Cron Schedule Configuration (if ENABLE_CRON=true) ---
        CRON_SCHEDULE="*/15 * * * *" # Every 15 minutes

        # --- Asset Copy Options for na-pipeline.sh ---
        COPY_SOURCE_IMAGES=true
        COPY_BASELINE_IMAGES=true

        # --- Behavior for workspace_na_pipeline.sh ---
        REMOVE_PROCESSED_DIRS=true
        PIPELINE_ENABLE_DEBUG_LOGGING=false
        PIPELINE_KEEP_TEMP_RUN_DIR=false

        # --- Module Paths on Host (Absolute, or relative to docker-wrapper/ if running docker-compose from here) ---
        # These point to your Git submodules on the HOST machine.
        LAYPA_MODULE=../laypa # Assumes submodules are one level up from docker-wrapper/
        LOGHI_HTR_MODULE=../loghi-htr
        LOGHI_TOOLING_MODULE=../loghi-tooling
        PRIMA_CORE_LIBS_MODULE=../prima-core-libs

        # --- Workspace and Destination Paths on Host ---
        # These MUST be ABSOLUTE paths on your HOST machine.
        WORKSPACE_PATH="/mnt/archive_scans/loghi_input_aezel"
        DESTINATION_PATH="/mnt/archive_scans/loghi_output_aezel"
        ```
    * **Important**:
        * Adjust `WORKSPACE_PATH` and `DESTINATION_PATH` to **absolute paths** on your host machine.
        * Ensure the `*_MODULE` paths correctly point to your local submodule directories. The example `../` assumes submodules are direct children of the `loghi-aezel` root, and `docker-compose` is run from `docker-wrapper/`.

3.  **Prepare Host Directories**:
    Ensure the directories specified for `WORKSPACE_PATH`, `DESTINATION_PATH`, and the submodule paths exist on your host machine and have appropriate read/write permissions for the user running Docker.
    ```bash
    # Example based on .env settings:
    mkdir -p /mnt/archive_scans/loghi_input_aezel
    mkdir -p /mnt/archive_scans/loghi_output_aezel
    # Ensure ../laypa, ../loghi-htr etc. exist relative to docker-wrapper/ or adjust paths.
    ```

4.  **Start the Docker Wrapper Service**:
    From the `docker-wrapper` directory:
    ```bash
    docker-compose up -d
    ```
    This command builds the `loghi-wrapper` image if it doesn't exist (based on `docker-wrapper/Dockerfile`) and starts the service in detached mode. The container will:
    * Start an internal Docker daemon (DinD).
    * If `ENABLE_CRON=true` in `.env`, configure and start a cron service.
    * The cron job (if enabled) will periodically execute `/app/workspace_na_pipeline.sh /workspace /destination` to process data.

5.  **Process Images**:
    * Place directories containing your images into the `WORKSPACE_PATH` you defined on your host. Each subdirectory within `WORKSPACE_PATH` is treated as a separate processing job.
        * Example: If `WORKSPACE_PATH` is `/mnt/archive_scans/loghi_input_aezel`, you would add folders like:
            * `/mnt/archive_scans/loghi_input_aezel/scan_batch_01/` (containing image files: .jpg, .png, .tif)
            * `/mnt/archive_scans/loghi_input_aezel/scan_batch_02/`
    * If cron is enabled, it will detect and process these directories.
    * Processed output (PageXML, TXT files, and optionally images) will be saved in subdirectories within your `DESTINATION_PATH` on the host.

6.  **Monitor and View Logs**:
    * **Wrapper Container Logs (Setup, Cron Activity)**:
        ```bash
        # From the docker-wrapper directory
        docker-compose logs -f loghi-wrapper
        ```
    * **Pipeline Script Logs**:
        The `workspace_na_pipeline.sh` script generates detailed logs for each run. These are stored inside the `loghi-wrapper` container in `/app/logs/run_YYYYMMDD_HHMMSS_PID/`. This `/app/logs` directory is mapped to a Docker volume named `loghi_wrapper_logs`.
        To find the host path of this volume:
        ```bash
        docker volume inspect loghi_wrapper_logs
        ```
        Navigate to the "Mountpoint" shown in the output to access the log files on your host.
    * **Cron Job Output (if enabled)**:
        The direct output of the cron command is logged to `/app/logs/pipeline_cron_runs.log` within the `loghi_wrapper_logs` volume. You can tail these logs live from your host after finding the volume mount point, or directly from the container:
        ```bash
        docker-compose exec -u ubuntu loghi-wrapper tail -f /app/logs/pipeline_cron_runs.log
        ```
    * **Internal Docker Daemon Logs**:
        Located at `/var/log/dockerd.log` inside the `loghi-wrapper` container. Useful for debugging DinD issues. Access via `docker-compose exec loghi-wrapper cat /var/log/dockerd.log`.

7.  **Stopping the Wrapper**:
    From the `docker-wrapper` directory:
    ```bash
    docker-compose down
    # To remove volumes (including logs and internal Docker storage):
    # docker-compose down -v
    ```

### Manual Pipeline Execution (for Debugging)

Even if cron is disabled or you want to force a run:

1.  **Ensure the wrapper is running**: `docker-compose up -d`
2.  **Place data**: Put a test directory (e.g., `my_test_batch`) with images into the `WORKSPACE_PATH` on your host. This will appear under `/workspace/my_test_batch` inside the container.
3.  **Execute the main pipeline script**:
    ```bash
    docker-compose exec -u ubuntu loghi-wrapper /bin/bash /app/workspace_na_pipeline.sh /workspace /destination
    ```
    This runs the processing logic immediately as the `ubuntu` user (which is how cron also runs it).

    To test `na-pipeline.sh` directly (more advanced, requires manual setup of input within container):
    ```bash
    # Example:
    # 1. Manually copy/mount data into a temp dir inside container, e.g., /tmp/manual_test/
    # 2. Then exec na-pipeline.sh:
    docker-compose exec -u ubuntu loghi-wrapper /bin/bash /app/na-pipeline.sh /tmp/manual_test /tmp/manual_output true true
    ```

## Troubleshooting

* **Permissions Errors**:
    * Ensure host directories for `WORKSPACE_PATH`, `DESTINATION_PATH`, and submodules have correct read/write permissions for the user Docker runs as.
    * The wrapper script attempts to manage internal permissions, but host permissions take precedence for volume mounts.
* **"Docker daemon is NOT responsive"** (in `na-pipeline.sh` logs):
    * Indicates an issue with the Docker-in-Docker setup. Check `loghi-wrapper` container logs and `/var/log/dockerd.log` inside it.
* **NVIDIA GPU Issues**:
    * Verify host NVIDIA drivers and NVIDIA Container Toolkit. Check `loghi-wrapper` logs for GPU errors. Run `nvidia-smi` on host.
* **Submodule Paths Incorrect**:
    * Double-check `*_MODULE` paths in `docker-wrapper/.env` against your project structure and where `docker-compose` is run.
* **Script Not Executable Errors**:
    * Ensure `.sh` files in the main project have execute permissions in Git (`git update-index --chmod=+x scriptname.sh`).
* **Stale Lock Files**:
    * `workspace_na_pipeline.sh` uses `/tmp/pipeline_cron.lock` (for cron) or `/tmp/workspace_na_pipeline.lock` (if run manually, check script). If a run crashes, manual removal via `docker-compose exec` might be needed.
* **Cron Job Not Running (if `ENABLE_CRON=true`)**:
    * Check `loghi-wrapper` logs for cron service startup. Verify `CRON_SCHEDULE`. Check `/app/logs/pipeline_cron_runs.log`.
* **XMLStarlet Errors** (in `xml2text.sh` logs):
    * `xmlstarlet` is included in the wrapper. Errors usually mean XML structure issues.

## Training New Models

The script `na-pipeline-train.sh` (located in the main `loghi-aezel` project directory) is provided for training. This `docker-wrapper` setup is primarily for inference, but the component Docker images built/pulled can be used as a basis for training environments. Consult original Loghi documentation for training specifics.

## Further Customization

* **Pipeline Steps**: Modify `na-pipeline.sh` in the main project.
* **Docker Images**: Update component Dockerfiles in `loghi-aezel/docker/` or `docker-wrapper/Dockerfile`. Rebuild images after changes.
* **Cron Behavior**: Adjust `CRON_SCHEDULE` or `ENABLE_CRON` in `docker-wrapper/.env`.

## Author / Maintainer

This "Loghi-Aezel" fork is developed and maintained by:

* **Arthur Rahimov**
    * Email: a.ragimov@aezel.eu
    * Organization: [Aezel](https://aezel.eu)
    * Personal Website: [ragmon.nl](https://ragmon.nl)
