FROM ubuntu:24.04

LABEL maintainer="Loghi Team"
LABEL description="Docker wrapper for Loghi HTR processing pipeline"

# Install dependencies including locales properly
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

# Set up locale properly
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /app /workspace /tmp/processing /app/logs /app/temp_workspace

WORKDIR /app

COPY . .

# Configure ubuntu user and docker group
RUN useradd -m -s /bin/bash -G sudo ubuntu || true
RUN echo "ubuntu:ubuntu" | chpasswd

# Create docker group if it doesn't exist
RUN groupadd -f docker

# Add ubuntu user to docker group
RUN usermod -aG docker ubuntu

# Configure Docker daemon
RUN mkdir -p /etc/docker && \
    echo '{"group": "docker"}' > /etc/docker/daemon.json

# Set ownership for directories
RUN chown -R ubuntu:ubuntu /app /workspace /tmp /app/logs /app/temp_workspace

# Give ubuntu user password-less sudo access
RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu

# Set proper permissions for directories
RUN chmod -R 777 /tmp /app/temp_workspace /app/logs

# Default command to keep container running
CMD ["tail", "-f", "/dev/null"]