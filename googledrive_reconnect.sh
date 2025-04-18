#!/bin/bash
# File: reconnect_gdrive.sh

# Define the path where Google Drive should be mounted in WSL
GDRIVE_PATH="G:"  # Adjust this path
MOUNT_POINT="/mnt/g"  # Or your preferred mount location

# Function to check if Google Drive is accessible
check_gdrive_access() {
  if [ -d "$GDRIVE_PATH" ] && ls "$GDRIVE_PATH" &>/dev/null; then
    return 0  # Accessible
  else
    return 1  # Not accessible
  fi
}

# Function to mount Google Drive
mount_gdrive() {
  echo "$(date): Attempting to remount Google Drive..."
  
  # Create mount point if it doesn't exist
  mkdir -p "$MOUNT_POINT"
  
  # Try to remount
  if sudo mount -t drvfs "$GDRIVE_PATH" "$MOUNT_POINT" &>/dev/null; then
    echo "$(date): Successfully mounted Google Drive to $MOUNT_POINT"
    return 0
  else
    echo "$(date): Failed to mount Google Drive" >> "$HOME/gdrive_reconnect.log"
    return 1
  fi
}

# Main logic
if ! check_gdrive_access; then
  echo "$(date): Google Drive not accessible, attempting to reconnect..." >> "$HOME/gdrive_reconnect.log"
  
  # Option 1: Restart WSL via PowerShell (requires admin privileges)
  # This part is commented out because it requires special setup
  # powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList 'wsl --shutdown; Start-Sleep -Seconds 2'"
  
  # Option 2: Try direct remounting
  mount_gdrive
else
  # Drive is accessible, check if our mount point is active
  if [ -d "$MOUNT_POINT" ] && ! mountpoint -q "$MOUNT_POINT"; then
    mount_gdrive
  fi
fi
