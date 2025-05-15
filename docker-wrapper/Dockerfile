# Use an NVIDIA base image that includes CUDA and drivers, or install them.
# Using an official NVIDIA CUDA image is often easier.
# Ensure the CUDA version is compatible with your host drivers and the tools you run.
# For example, if your tools need CUDA 11.x or 12.x:
FROM nvidia/cuda:12.1.0-base-ubuntu22.04
# Or stick to your ubuntu:24.04 and install drivers/toolkit manually (more complex)
# FROM ubuntu:24.04

LABEL maintainer="Loghi Team"
LABEL description="Docker wrapper for Loghi HTR processing pipeline (DinD with GPU support)"

# Set DEBIAN_FRONTEND to noninteractive to avoid prompts during apt-get install
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies, Python, Docker CE, and NVIDIA Container Toolkit
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    tree \
    gnupg \
    lsb-release \
    git \
    cron \
    nano \
    xmlstarlet \
    python3 \
    python3-pip \
    tzdata \
    sudo \
    locales \
    # Dependencies for NVIDIA Container Toolkit & Docker
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Set up locale properly
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install Docker CE (if not using a base image that already has it for DinD)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA Container Toolkit (for the DinD setup)
# This allows the dockerd *inside* this container to manage NVIDIA GPUs.
RUN curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nvidia-container-toolkit \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories for the application
RUN mkdir -p /app /workspace /tmp/processing /app/logs /app/temp_workspace /tmp/matplotlib_cache_wrapper

WORKDIR /app

# Copy application files (assuming your build context is the parent of docker-wrapper)
# COPY ./docker-wrapper/app_content/ /app/ 
COPY . .

# If your scripts (workspace_na_pipeline.sh, etc.) are in docker-wrapper/ itself:
# COPY ./*.sh /app/
# Adjust the COPY command based on your actual project structure.
# For this example, let's assume they are copied via the app_content directory or similar.
# If your scripts are in the root of the context (parent of docker-wrapper), use:
# COPY ./*.sh /app/ # If scripts are at context root
# COPY ./laypa /app/laypa # etc. for modules if not using docker-compose volumes for them during dev

# Configure ubuntu user
RUN useradd -m -s /bin/bash -G sudo ubuntu || true # Allow if user already exists
RUN echo "ubuntu:ubuntu" | chpasswd
RUN groupadd -f docker || true # Create docker group if it doesn't exist
RUN usermod -aG docker ubuntu # Add ubuntu to docker group for using the inner Docker CLI

# Give ubuntu user password-less sudo access
RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu && chmod 0440 /etc/sudoers.d/ubuntu

# Set ownership for directories that ubuntu user will primarily interact with
# /var/lib/docker will be managed by root (the inner dockerd)
RUN chown -R ubuntu:ubuntu /app /home/ubuntu /tmp/matplotlib_cache_wrapper
# Permissions for /tmp, /app/logs, /app/temp_workspace will be set in docker-compose command

# The CMD will be overridden by docker-compose, but good to have a default.
CMD ["sh", "-c", "echo 'Default CMD: Container started. Configure inner Docker and run scripts.' && tail -f /dev/null"]
