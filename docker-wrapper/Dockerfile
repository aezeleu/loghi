FROM ubuntu:24.04

LABEL maintainer="Loghi Team"
LABEL description="Docker wrapper for Loghi HTR processing pipeline"

# Install dependencies
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    cron \
    nano \
    xmlstarlet \
    python3 \
    python3-pip \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Install Docker
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce docker-ce-cli containerd.io \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /app /app/config /app/logs /app/data /app/temp /app/models /app/backup

# Create volume directories for mounting
RUN mkdir -p /app/modules/laypa \
    /app/modules/loghi-htr \
    /app/modules/loghi-tooling \
    /app/modules/prima-core-libs

WORKDIR /app

# First copy everything needed from the docker-wrapper directory
COPY config/* /app/config/
COPY scripts/* /app/scripts/

# For build context that includes the parent directory
# Copy necessary files from parent directory if they exist
COPY na-pipeline.sh na-pipeline-train.sh pipeline_wrapper.sh generate-images.sh \
     workspace_na_pipeline.sh xml2text.sh create_train_data.sh /app/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh /app/*.sh || true

# Set up cron
COPY config/crontab /etc/cron.d/loghi-cron
RUN chmod 0644 /etc/cron.d/loghi-cron \
    && touch /var/log/cron.log

# Environment variables
ENV LOGHI_DATA_DIR=/app/data
ENV LOGHI_CONFIG_DIR=/app/config
ENV LOGHI_LOGS_DIR=/app/logs
ENV LOGHI_MODELS_DIR=/app/models
ENV LOGHI_MODULES_DIR=/app/modules
ENV PATH="/app:/app/scripts:${PATH}"

# Create entrypoint script
COPY scripts/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

VOLUME ["/app/data", "/app/logs", "/app/config", "/app/models", "/app/modules"]

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["start"] 