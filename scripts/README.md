# GPS Data Capture - Installation Scripts

This folder contains scripts for installing the GPS Data Capture Worker Service as a systemd service on Linux systems (including Raspberry Pi).

## Scripts

### 1. `install-systemd.sh`
Installs the GPS Data Capture service as a systemd service with shared data access.

### 2. `uninstall-systemd.sh`
Removes the GPS Data Capture service and optionally cleans up data.

## Quick Start

### Installation

```bash
# Make script executable
chmod +x scripts/install-systemd.sh

# Install for Raspberry Pi (ARM64)
sudo scripts/install-systemd.sh

# Install for x64 Linux
sudo scripts/install-systemd.sh linux-x64
```

### Uninstallation

```bash
# Make script executable
chmod +x scripts/uninstall-systemd.sh

# Remove service and delete data
sudo scripts/uninstall-systemd.sh

# Remove service but keep data
sudo scripts/uninstall-systemd.sh --keep-data
```

## What the Installation Does

### 1. **Creates Service User & Group**
- User: `gpsservice`
- Group: `gpsdata`
- Added to `dialout` group for serial port access

### 2. **Creates Shared Data Directory**
- Location: `/var/gpsdatacapture/`
- Permissions: `775` (rwxrwxr-x)
- Group: `gpsdata`
- SGID bit set (new files inherit group)

### 3. **Installs Application**
- Location: `/opt/gpsdatacapture/`
- Self-contained .NET deployment
- Configured to use shared data directory

### 4. **Sets Up Systemd Service**
- Service name: `gpsdatacapture`
- Auto-starts on boot
- Runs as `gpsservice` user
- Logs to systemd journal

## Data Access Configuration

### Default Setup
The installation creates a **shared data directory** at `/var/gpsdatacapture/` where:
- ✅ The service can read/write GPS data files
- ✅ All users in the `gpsdata` group can read/write/delete files
- ✅ Files are owned by `gpsservice:gpsdata`
- ✅ Directory permissions: `775` (rwxrwxr-x)
- ✅ SGID bit ensures new files inherit the `gpsdata` group

### Adding Users to Access GPS Data

To allow a user to access and modify GPS data files:

```bash
# Add user to gpsdata group
sudo usermod -a -G gpsdata username

# User must log out and back in for changes to take effect
```

After logging back in, the user can:
```bash
# View GPS data files
ls -lh /var/gpsdatacapture/

# View GPS data
cat /var/gpsdatacapture/gps_data_20241014.csv
tail -f /var/gpsdatacapture/gps_data_20241014.ndjson

# Delete old files
rm /var/gpsdatacapture/gps_data_20241001.*

# Move files
mv /var/gpsdatacapture/*.csv ~/backups/
```

### Current User Quick Access

To give yourself access immediately after installation:

```bash
# Add your user to the group
sudo usermod -a -G gpsdata $USER

# Apply group changes without logging out (may not work in all shells)
newgrp gpsdata

# Or log out and back in for permanent effect
```

## Service Management

### Check Service Status
```bash
sudo systemctl status gpsdatacapture
```

### View Live Logs
```bash
sudo journalctl -u gpsdatacapture -f
```

### Start/Stop/Restart
```bash
sudo systemctl start gpsdatacapture
sudo systemctl stop gpsdatacapture
sudo systemctl restart gpsdatacapture
```

### Enable/Disable Auto-Start
```bash
sudo systemctl enable gpsdatacapture   # Start on boot
sudo systemctl disable gpsdatacapture  # Don't start on boot
```

### View All Logs
```bash
# Last 100 lines
sudo journalctl -u gpsdatacapture -n 100

# Logs since boot
sudo journalctl -u gpsdatacapture -b

# Logs from today
sudo journalctl -u gpsdatacapture --since today
```

## Architecture Support

The installation script supports:
- **`linux-arm64`** - Raspberry Pi 3/4/5, ARM64 devices (default)
- **`linux-arm`** - Older ARM devices
- **`linux-x64`** - Standard x64 Linux servers

## Directory Structure After Installation

```
/opt/gpsdatacapture/                    # Application files
├── GpsDataCaptureWorkerService         # Executable
├── appsettings.json                    # Configuration (updated)
├── appsettings.json.bak                # Original config backup
└── [other DLL files...]

/var/gpsdatacapture/                    # Data directory (shared access)
├── gps_data_20241014.csv              # Daily CSV file
├── gps_data_20241014.ndjson           # Daily NDJSON file
└── [previous days...]

/etc/systemd/system/
└── gpsdatacapture.service              # Systemd service file
```

## File Permissions Example

```bash
$ ls -lah /var/gpsdatacapture/
drwxrwsr-x 2 gpsservice gpsdata 4.0K Oct 14 12:00 .
-rw-rw-r-- 1 gpsservice gpsdata  15K Oct 14 12:30 gps_data_20241014.csv
-rw-rw-r-- 1 gpsservice gpsdata  12K Oct 14 12:30 gps_data_20241014.ndjson
```

Explanation:
- `drwxrwsr-x` - Directory with SGID bit (s)
- `rw-rw-r--` - Files readable/writable by owner and group
- `gpsservice:gpsdata` - Owner:Group

## Troubleshooting

### Service Won't Start
```bash
# Check detailed status
sudo systemctl status gpsdatacapture -l

# View error logs
sudo journalctl -u gpsdatacapture -n 50
```

### Permission Denied on Serial Port
```bash
# Verify service user is in dialout group
groups gpsservice

# If not, add manually
sudo usermod -a -G dialout gpsservice
sudo systemctl restart gpsdatacapture
```

### Can't Access Data Files
```bash
# Check if you're in the gpsdata group
groups

# If not, add yourself
sudo usermod -a -G gpsdata $USER

# Log out and back in, or use newgrp
newgrp gpsdata
```

### GPS Device Not Detected
```bash
# List USB serial devices
ls -l /dev/ttyUSB* /dev/ttyACM*

# Check kernel messages
dmesg | grep tty

# Manually set port in config
sudo nano /opt/gpsdatacapture/appsettings.json
# Change: "PortName": "/dev/ttyUSB0"

# Restart service
sudo systemctl restart gpsdatacapture
```

## Updating the Service

To update to a new version:

```bash
# Stop the service
sudo systemctl stop gpsdatacapture

# Pull latest code
git pull

# Run installation script (will update in place)
sudo scripts/install-systemd.sh

# Service will auto-start
```

## Security Considerations

### Service Hardening
The systemd service includes security options:
- `NoNewPrivileges=true` - Prevents privilege escalation
- `PrivateTmp=true` - Isolated /tmp directory
- Runs as non-root user (`gpsservice`)

### Data Access
- Only users in `gpsdata` group can modify files
- SGID ensures consistent group ownership
- Files are not world-writable

### Serial Port Access
- Service user has minimal permissions
- Only added to `dialout` group for serial port access

## Requirements

- .NET 8.0 Runtime or SDK
- Systemd (most modern Linux distributions)
- Root access (sudo)
- USB serial port access (for GPS device)

## Support

For issues or questions:
1. Check service logs: `sudo journalctl -u gpsdatacapture -f`
2. Verify permissions: `ls -lah /var/gpsdatacapture/`
3. Check GPS device: `ls -l /dev/ttyUSB* /dev/ttyACM*`

