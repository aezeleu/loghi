FROM ubuntu:24.04

LABEL maintainer="Loghi Team"
LABEL description="Docker wrapper for Loghi HTR processing pipeline"

# Install dependencies including locales
RUN apt-get update && apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Install Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories with proper permissions
RUN mkdir -p /app /workspace /tmp/processing
RUN chmod 777 /tmp /tmp/processing

WORKDIR /app

COPY . .

# Configure ubuntu user and docker group (separated into discrete steps)
# Set ubuntu user password (should work whether user already exists or not)
RUN echo "ubuntu:ubuntu" | chpasswd || true

# Add ubuntu user to sudo group
RUN usermod -aG sudo ubuntu || true

# Create docker group if it doesn't exist
RUN groupadd -f docker

# Add ubuntu user to docker group
RUN usermod -aG docker ubuntu

# Configure Docker daemon
RUN mkdir -p /etc/docker && \
    echo '{"group": "docker"}' > /etc/docker/daemon.json

# Set ownership for app and workspace directories
RUN chown -R ubuntu:ubuntu /app /workspace

# Give ubuntu user password-less sudo access
RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu

# Create startup script to ensure docker.sock permissions are correct
RUN echo '#!/bin/bash\nchmod 666 /var/run/docker.sock\nchmod -R 777 /tmp\necho "Docker socket and temp directory permissions fixed"\nexec "$@"' > /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Set our custom entrypoint that fixes permissions
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command to keep container running
CMD ["tail", "-f", "/dev/null"]