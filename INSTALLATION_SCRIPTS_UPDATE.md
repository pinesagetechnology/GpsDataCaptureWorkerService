# Installation Scripts Update - Azure Storage Configuration

## Summary

Updated the installation scripts for both Linux (systemd) and Windows to include interactive prompts for Azure Storage configuration during installation. This makes it easy to set up the GPS Data Capture service with Azure Blob Storage integration without manual configuration file editing.

## Changes Made

### 1. Updated `scripts/install-systemd.sh` (Linux/Raspberry Pi)

**New Features:**
- ✨ **Interactive Azure Storage Configuration** (Step 5)
  - Prompts user to configure Azure Storage during installation
  - Asks for Azure Storage connection string
  - Asks for container name (default: `gps-data`)
  - Automatically updates `appsettings.json` with provided values
  - Skips configuration if user declines (can configure later)

**Changes:**
- Added Step 5: "Configure Azure Storage (if needed)"
- Renumbered subsequent steps (6-11)
- Updates both `DataDirectory` and Azure Storage settings in `appsettings.json`
- Backs up original `appsettings.json` before modifications

**User Experience:**
```bash
Step 5: Azure Storage Configuration

Do you want to configure Azure Storage for GPS data upload?
This allows the service to automatically upload GPS data to Azure Blob Storage.

Configure Azure Storage? (y/N): y

Azure Storage Configuration:

Enter your Azure Storage connection string:
(You can find this in Azure Portal > Storage Account > Access Keys)
Connection String: [user enters connection string]

Enter the container name for GPS data:
Container Name [gps-data]: [user can press Enter for default or enter custom name]

✓ Azure Storage will be configured with container: gps-data
```

### 2. Created `scripts/install-windows.ps1` (NEW FILE)

**New Windows Installation Script:**
- 🆕 Complete Windows installation script
- ✨ Interactive Azure Storage configuration
- Creates Windows Service automatically
- Configures data directory
- Updates `appsettings.json` with Azure Storage settings
- Proper error handling and colored output
- Service recovery configuration (auto-restart on failure)

**Features:**
- Runs as Administrator (required)
- Builds and publishes application for Windows (win-x64)
- Installs to `C:\Services\GpsDataCapture\`
- Data directory: `C:\ProgramData\GpsDataCapture\`
- Creates Windows Service: `GpsDataCaptureService`
- Configures service to auto-start on boot
- Prompts for Azure Storage configuration
- Updates `appsettings.json` automatically
- Starts service and shows status

**User Experience:**
```powershell
Step 4: Azure Storage Configuration

Do you want to configure Azure Storage for GPS data upload?
This allows the service to automatically upload GPS data to Azure Blob Storage.

Configure Azure Storage? (y/N): y

Azure Storage Configuration:

Enter your Azure Storage connection string:
(You can find this in Azure Portal > Storage Account > Access Keys)
Connection String: [user enters connection string]

Enter the container name for GPS data:
Container Name [gps-data]: [user can press Enter for default or enter custom name]

✓ Azure Storage will be configured with container: gps-data
```

### 3. Updated `scripts/README.md`

**Documentation Updates:**
- Added Windows installation instructions
- Documented Azure Storage configuration prompts
- Added section on "What the Installation Does"
- Added "Azure Storage Configuration" section with:
  - During installation configuration
  - After installation configuration
  - Getting Azure Storage connection string
  - Verifying Azure Storage upload
- Updated all command examples for both Linux and Windows
- Added Windows-specific commands and paths

## Benefits

### 1. **Simplified Setup**
- No need to manually edit `appsettings.json`
- One-step installation with Azure Storage ready to go
- Default values provided for common settings

### 2. **Better User Experience**
- Interactive prompts guide users through configuration
- Clear instructions on where to find Azure Storage credentials
- Option to skip and configure later

### 3. **Production Ready**
- Automatic backup of original `appsettings.json`
- Proper error handling
- Service starts immediately with correct configuration

### 4. **Cross-Platform Support**
- Both Linux and Windows installation scripts
- Consistent user experience across platforms
- Platform-specific optimizations

### 5. **Flexibility**
- Users can accept default container name or customize
- Can skip Azure Storage configuration during install
- Easy to reconfigure later by editing `appsettings.json`

## Usage Examples

### Example 1: Linux Installation with Azure Storage

```bash
sudo ./scripts/install-systemd.sh

# Script prompts:
Configure Azure Storage? (y/N): y
Connection String: DefaultEndpointsProtocol=https;AccountName=mygpsdata;AccountKey=abc123...
Container Name [gps-data]: production-gps

# Result:
# ✓ Service installed
# ✓ Azure Storage configured with container: production-gps
# ✓ Service started and uploading to Azure
```

### Example 2: Linux Installation without Azure Storage

```bash
sudo ./scripts/install-systemd.sh

# Script prompts:
Configure Azure Storage? (y/N): n

# Result:
# ℹ Skipping Azure Storage configuration
# ✓ Service installed
# ✓ Service saving data to local files
```

### Example 3: Windows Installation with Azure Storage

```powershell
.\scripts\install-windows.ps1

# Script prompts:
Configure Azure Storage? (y/N): y
Connection String: DefaultEndpointsProtocol=https;AccountName=mygpsdata;AccountKey=abc123...
Container Name [gps-data]: [press Enter for default]

# Result:
# ✓ Service installed
# ✓ Azure Storage configured with container: gps-data
# ✓ Service started and uploading to Azure
```

### Example 4: Configure Azure Storage After Installation

**Linux:**
```bash
# Edit config
sudo nano /opt/gpsdatacapture/appsettings.json

# Update settings:
"Mode": "SendToAzureStorage",
"AzureStorageConnectionString": "DefaultEndpointsProtocol=https;...",
"AzureStorageContainerName": "gps-data"

# Restart
sudo systemctl restart gpsdatacapture
```

**Windows:**
```powershell
# Edit config
notepad C:\Services\GpsDataCapture\appsettings.json

# Update settings:
"Mode": "SendToAzureStorage",
"AzureStorageConnectionString": "DefaultEndpointsProtocol=https;...",
"AzureStorageContainerName": "gps-data"

# Restart
Restart-Service -Name GpsDataCaptureService
```

## Technical Details

### Linux Script Updates

**File:** `scripts/install-systemd.sh`

**Modified Sections:**
- Added Step 5: Azure Storage Configuration prompts
- Updated Step 6: Enhanced `appsettings.json` update logic
- Renumbered Steps 7-11

**New Logic:**
```bash
# Prompt for Azure Storage configuration
read -p "Configure Azure Storage? (y/N): " CONFIGURE_AZURE

if [[ "$CONFIGURE_AZURE" =~ ^[Yy]$ ]]; then
    read -p "Connection String: " AZURE_CONNECTION
    read -p "Container Name [gps-data]: " AZURE_CONTAINER_INPUT
    
    # Update appsettings.json
    sed -i "s|\"AzureStorageConnectionString\": \"[^\"]*\"|\"AzureStorageConnectionString\": \"${AZURE_CONNECTION}\"|g"
    sed -i "s|\"AzureStorageContainerName\": \"[^\"]*\"|\"AzureStorageContainerName\": \"${AZURE_CONTAINER}\"|g"
fi
```

### Windows Script Creation

**File:** `scripts/install-windows.ps1` (NEW)

**Key Features:**
- PowerShell script with `#Requires -RunAsAdministrator`
- Color-coded output functions (Success, Info, Warning, Error, Header)
- Build and publish for win-x64
- Service creation using `New-Service`
- Service recovery configuration using `sc.exe failure`
- JSON manipulation using `ConvertFrom-Json` and `ConvertTo-Json`
- Automatic service start and status check

**Script Structure:**
1. Check prerequisites (.NET SDK, admin rights)
2. Stop and remove existing service if present
3. Create data directory
4. Build and publish application
5. **Prompt for Azure Storage configuration** ✨
6. **Update `appsettings.json` with Azure settings** ✨
7. Create Windows Service
8. Configure service recovery
9. Start service
10. Show status and usage instructions

## Files Modified/Created

### Modified Files:
1. `scripts/install-systemd.sh` - Added Azure Storage prompts
2. `scripts/README.md` - Updated documentation

### Created Files:
1. `scripts/install-windows.ps1` - New Windows installation script
2. `INSTALLATION_SCRIPTS_UPDATE.md` - This document

## Testing Recommendations

### Linux Testing:
```bash
# Test with Azure Storage
sudo ./scripts/install-systemd.sh
# Select "y" for Azure Storage, enter test credentials

# Verify configuration
sudo cat /opt/gpsdatacapture/appsettings.json | grep Azure

# Check service status
sudo systemctl status gpsdatacapture

# Check logs
sudo journalctl -u gpsdatacapture -f
```

### Windows Testing:
```powershell
# Test with Azure Storage (as Administrator)
.\scripts\install-windows.ps1
# Select "y" for Azure Storage, enter test credentials

# Verify configuration
Get-Content C:\Services\GpsDataCapture\appsettings.json | Select-String Azure

# Check service status
Get-Service GpsDataCaptureService

# Check logs
Get-EventLog -LogName Application -Source GpsDataCaptureWorkerService -Newest 10
```

## Security Considerations

### Connection String Security:
1. ✅ Connection strings are not logged or displayed in output
2. ✅ Original `appsettings.json` is backed up before modifications
3. ✅ Users are reminded where to find connection strings in Azure Portal
4. ⚠️ Connection strings are stored in `appsettings.json` (consider using environment variables for production)

### Recommendations:
- Use environment variables for production deployments
- Rotate Azure Storage keys regularly
- Use Azure Managed Identity when running on Azure VMs
- Restrict container access using Azure RBAC

## Migration Guide

### For Existing Installations:

**Option 1: Re-run installation script**
```bash
# Linux
sudo systemctl stop gpsdatacapture
sudo ./scripts/install-systemd.sh
# Answer prompts to configure Azure Storage

# Windows
Stop-Service -Name GpsDataCaptureService
.\scripts\install-windows.ps1
# Answer prompts to configure Azure Storage
```

**Option 2: Manual configuration**
Edit `appsettings.json` manually and restart the service (see Example 4 above)

## Future Enhancements

Potential improvements for future versions:
- [ ] Support for Azure Managed Identity authentication
- [ ] Validation of Azure Storage connection string during installation
- [ ] Option to test Azure Storage connection before completing installation
- [ ] Support for Azure Key Vault for storing connection strings
- [ ] Silent installation mode with command-line parameters
- [ ] Configuration file import/export for easy replication

---

**Implementation Date:** October 15, 2024
**Status:** ✅ Complete and Ready for Use

