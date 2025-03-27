# Troubleshooting Guide

This guide provides solutions for common issues encountered when using the Loghi pipeline.

## Path and Directory Issues

### Special Characters in Paths
**Problem**: Scripts fail when processing directories with spaces or special characters.
**Solution**: 
- Use proper path escaping in scripts
- Ensure all paths are properly quoted
- Use `${variable}` syntax for variable expansion

### Directory Permissions
**Problem**: Scripts cannot access or write to directories.
**Solution**:
- Check directory permissions: `ls -la /path/to/directory`
- Ensure user has write permissions: `chmod u+w /path/to/directory`
- Check ownership: `chown -R user:group /path/to/directory`

## Docker Issues

### Docker Not Running
**Problem**: Scripts fail with Docker-related errors.
**Solution**:
- Check Docker service: `systemctl status docker`
- Start Docker: `sudo systemctl start docker`
- Verify Docker installation: `docker --version`

### Docker Image Issues
**Problem**: Docker images are missing or outdated.
**Solution**:
- Pull required images:
  ```bash
  docker pull loghi/docker.laypa
  docker pull loghi/docker.htr
  docker pull loghi/docker.loghi-tooling
  ```
- Check image status: `docker images | grep loghi`

### Docker Permissions
**Problem**: Permission denied when running Docker commands.
**Solution**:
- Add user to docker group: `sudo usermod -aG docker $USER`
- Log out and back in for changes to take effect
- Verify group membership: `groups $USER`

## Processing Issues

### File Format Problems
**Problem**: Scripts fail to process certain image files.
**Solution**:
- Verify file format: `file /path/to/image`
- Ensure images are in supported formats (JPG, PNG)
- Check image integrity: `identify /path/to/image`

### Memory Issues
**Problem**: Scripts fail due to insufficient memory.
**Solution**:
- Check available memory: `free -h`
- Monitor memory usage: `top`
- Adjust Docker memory limits if needed

### Disk Space Issues
**Problem**: Scripts fail due to insufficient disk space.
**Solution**:
- Check disk space: `df -h`
- Clean up temporary files
- Ensure sufficient space in output directory

## CRON Job Issues

### Lock File Problems
**Problem**: Multiple instances of scripts running simultaneously.
**Solution**:
- Check lock file: `ls -l /tmp/pipeline_wrapper.lock`
- Remove stale lock: `rm /tmp/pipeline_wrapper.lock`
- Verify CRON job: `crontab -l`

### CRON Logging
**Problem**: No logs from CRON jobs.
**Solution**:
- Check CRON logs: `grep CRON /var/log/syslog`
- Verify log file permissions
- Ensure proper redirection in CRON entry

## Testing and Debugging

### Test Data Generation
**Problem**: Generated test images are not suitable.
**Solution**:
- Adjust image quality settings
- Use different fonts
- Modify noise levels
- Check text content

### Pipeline Testing
**Problem**: Pipeline fails with test data.
**Solution**:
- Run with verbose logging
- Check intermediate files
- Verify directory structure
- Test with minimal dataset

## Common Error Messages

### "No such file or directory"
- Verify path exists
- Check file permissions
- Ensure proper escaping

### "Permission denied"
- Check file permissions
- Verify user permissions
- Check directory ownership

### "Docker daemon is not running"
- Start Docker service
- Check Docker status
- Verify Docker installation

## Getting Help

If you encounter issues not covered in this guide:
1. Check the log files in the `logs` directory
2. Review the [README.md](README.md) for setup instructions
3. Check the [CRON Setup Guide](cron_setup_guide.md) for automation issues
4. Create an issue on the GitHub repository 