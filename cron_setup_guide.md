# CRON Setup Guide for Workspace Pipeline

## Quick Installation
1. Clone the repository:
```bash
git clone <repository-url>
cd loghi-main
```

2. Run the installation script:
```bash
chmod +x install_pipeline.sh
./install_pipeline.sh
```

## Manual Installation

### Prerequisites
- Ensure xmlstarlet is installed: `sudo apt-get install xmlstarlet`
- Verify Git is installed and configured
- Set up proper permissions for the workspace directory
- Configure Google Drive access (if required)
- Docker installed and configured
- NVIDIA GPU drivers (if using GPU)

### 1. Environment Setup
```bash
# Create a dedicated log directory
mkdir -p ~/pipeline_logs
```

### 2. Script Setup
1. Make all scripts executable:
```bash
chmod +x pipeline_wrapper.sh
chmod +x health-check.sh
chmod +x workspace_na_pipeline.sh
chmod +x xml2text.sh
chmod +x na-pipeline.sh
```

2. Verify script permissions:
```bash
ls -l *.sh
```

### 3. Set Up CRON Job
1. Edit crontab:
```bash
crontab -e
```

2. Add the following lines:
```
# Pipeline execution every 2 minutes
*/2 * * * * /home/default/Companies/Archive/loghi-main/pipeline_wrapper.sh

# Log rotation (daily at midnight)
0 0 * * * find ~/pipeline_logs -type f -mtime +7 -exec rm {} \;
```

## Monitoring and Maintenance

### Log Files
Monitor these files for issues:
- `xml_conversion_errors.log`
- Pipeline logs in `~/pipeline_logs/`
- Git pull logs for merge conflicts
- Health check logs

### Health Checks
The pipeline includes automatic health checks for:
- Disk space (minimum 10GB)
- Memory (minimum 32GB)
- Docker installation and images
- Required model files
- GPU availability (if enabled)

### Backup Information
- Backup frequency: Every pipeline run (2 minutes)
- Backup location: Defined in workspace_na_pipeline.sh
- Retention policy: 7 days (configured in CRON job)

## Troubleshooting
1. Check log files in `~/pipeline_logs/`
2. Verify xmlstarlet installation: `xmlstarlet --version`
3. Ensure proper file permissions
4. Verify Git credentials are configured correctly
5. Check Docker status: `docker info`
6. Verify GPU status: `nvidia-smi` (if using GPU)

## Important Notes
- The pipeline runs every 2 minutes
- Each run creates timestamped log files
- Failed XML conversions are logged separately
- Git updates are tracked and summarized
- Workspace is backed up before processing
- Health checks run before each pipeline execution
- Log files are automatically rotated after 7 days

## Updating the Pipeline
1. Pull latest changes:
```bash
git pull origin main
```

2. Re-run installation script:
```bash
./install_pipeline.sh
```

3. Verify CRON jobs:
```bash
crontab -l
``` 