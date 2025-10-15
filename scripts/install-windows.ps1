###############################################################################
# GPS Data Capture Worker Service - Windows Installation Script
# 
# This script installs the GPS Data Capture service as a Windows Service
#
# Usage: Run as Administrator
#   .\install-windows.ps1
###############################################################################

#Requires -RunAsAdministrator

# Configuration
$ServiceName = "GpsDataCaptureService"
$AppName = "GpsDataCaptureWorkerService"
$InstallDir = "C:\Services\GpsDataCapture"
$DataDir = "C:\ProgramData\GpsDataCapture"
$DisplayName = "GPS Data Capture Worker Service"
$Description = "Captures GPS data from NMEA-compatible devices and saves to files or sends to API/Azure Storage"

# Colors for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Header { Write-Host $args -ForegroundColor Blue }

Write-Header "================================================================"
Write-Header "  GPS Data Capture Worker Service - Windows Installation"
Write-Header "================================================================"
Write-Host ""

# Detect project directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$CsprojPath = Join-Path $ProjectDir "$AppName\$AppName.csproj"

Write-Warning "Configuration:"
Write-Host "  Project Directory: $ProjectDir"
Write-Host "  Install Directory: $InstallDir"
Write-Host "  Data Directory: $DataDir"
Write-Host ""

# Check if .NET is installed
Write-Info "Checking for .NET SDK..."
try {
    $dotnetVersion = dotnet --version
    Write-Success "✓ .NET SDK found: $dotnetVersion"
} catch {
    Write-Error "✗ Error: .NET SDK is not installed"
    Write-Host "Please install .NET 8.0 SDK from: https://dotnet.microsoft.com/download"
    exit 1
}
Write-Host ""

# Check if project exists
if (-not (Test-Path $CsprojPath)) {
    Write-Error "✗ Error: Project file not found at $CsprojPath"
    exit 1
}

# Step 1: Stop existing service if running
Write-Warning "Step 1: Checking for existing service..."
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($existingService) {
    if ($existingService.Status -eq 'Running') {
        Write-Info "Stopping existing service..."
        Stop-Service -Name $ServiceName -Force
        Write-Success "✓ Service stopped"
    }
    
    Write-Info "Removing existing service..."
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
    Write-Success "✓ Existing service removed"
}
Write-Host ""

# Step 2: Create data directory
Write-Warning "Step 2: Creating data directory..."
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    Write-Success "✓ Created data directory: $DataDir"
} else {
    Write-Info "ℹ Data directory already exists"
}
Write-Host ""

# Step 3: Build and publish the application
Write-Warning "Step 3: Building and publishing application..."
Push-Location (Join-Path $ProjectDir $AppName)

Write-Info "Running: dotnet publish -c Release -r win-x64 --self-contained -o `"$InstallDir`""
$publishResult = dotnet publish -c Release -r win-x64 --self-contained -o "$InstallDir" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "✗ Build failed"
    Write-Host $publishResult
    Pop-Location
    exit 1
}

Pop-Location
Write-Success "✓ Application published to $InstallDir"
Write-Host ""

# Step 4: Configure Azure Storage (if needed)
Write-Warning "Step 4: Azure Storage Configuration"
Write-Host ""
Write-Host "Do you want to configure Azure Storage for GPS data upload?"
Write-Host "This allows the service to automatically upload GPS data to Azure Blob Storage."
Write-Host ""

$configureAzure = Read-Host "Configure Azure Storage? (y/N)"

$azureConnection = ""
$azureContainer = "gps-data"

if ($configureAzure -match '^[Yy]$') {
    Write-Host ""
    Write-Info "Azure Storage Configuration:"
    Write-Host ""
    
    # Prompt for connection string
    Write-Host "Enter your Azure Storage connection string:"
    Write-Host "(You can find this in Azure Portal > Storage Account > Access Keys)"
    $azureConnection = Read-Host "Connection String"
    
    # Prompt for container name with default
    Write-Host ""
    Write-Host "Enter the container name for GPS data:"
    $containerInput = Read-Host "Container Name [gps-data]"
    
    # Use default if empty
    if ($containerInput) {
        $azureContainer = $containerInput
    }
    
    Write-Host ""
    Write-Success "✓ Azure Storage will be configured with container: $azureContainer"
} else {
    Write-Info "ℹ Skipping Azure Storage configuration"
}
Write-Host ""

# Step 5: Update appsettings.json
Write-Warning "Step 5: Configuring application settings..."
$appSettingsFile = Join-Path $InstallDir "appsettings.json"

if (Test-Path $appSettingsFile) {
    # Backup original
    Copy-Item $appSettingsFile "$appSettingsFile.bak" -Force
    
    # Read appsettings.json
    $appSettings = Get-Content $appSettingsFile -Raw | ConvertFrom-Json
    
    # Update DataDirectory
    $appSettings.GpsSettings.DataDirectory = $DataDir
    Write-Success "✓ Updated DataDirectory to: $DataDir"
    
    # Update Azure Storage settings if configured
    if ($azureConnection) {
        $appSettings.GpsSettings.AzureStorageConnectionString = $azureConnection
        $appSettings.GpsSettings.AzureStorageContainerName = $azureContainer
        Write-Success "✓ Updated Azure Storage connection string"
        Write-Success "✓ Updated Azure Storage container name to: $azureContainer"
    }
    
    # Save updated appsettings.json
    $appSettings | ConvertTo-Json -Depth 10 | Set-Content $appSettingsFile -Encoding UTF8
    Write-Info "ℹ Backup saved: $appSettingsFile.bak"
} else {
    Write-Warning "⚠ Warning: appsettings.json not found"
}
Write-Host ""

# Step 6: Create Windows Service
Write-Warning "Step 6: Creating Windows Service..."
$exePath = Join-Path $InstallDir "$AppName.exe"

if (-not (Test-Path $exePath)) {
    Write-Error "✗ Error: Executable not found at $exePath"
    exit 1
}

$serviceParams = @{
    Name = $ServiceName
    BinaryPathName = "`"$exePath`""
    DisplayName = $DisplayName
    Description = $Description
    StartupType = "Automatic"
}

# Create the service using New-Service
try {
    New-Service @serviceParams -ErrorAction Stop | Out-Null
    Write-Success "✓ Windows Service created"
} catch {
    Write-Error "✗ Failed to create service: $_"
    exit 1
}

# Configure service recovery options
Write-Info "Configuring service recovery options..."
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
Write-Success "✓ Service recovery configured (auto-restart on failure)"
Write-Host ""

# Step 7: Start the service
Write-Warning "Step 7: Starting service..."
try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq 'Running') {
        Write-Success "✓ Service started successfully"
    } else {
        Write-Warning "⚠ Service status: $($service.Status)"
        Write-Host "Check Event Viewer > Windows Logs > Application for errors"
    }
} catch {
    Write-Error "✗ Failed to start service: $_"
    Write-Host "Check Event Viewer > Windows Logs > Application for errors"
}
Write-Host ""

# Step 8: Show service status
Write-Warning "Step 8: Service Status"
Get-Service -Name $ServiceName | Format-Table -AutoSize
Write-Host ""

# Summary and instructions
Write-Success "================================================================"
Write-Success "  Installation Complete!"
Write-Success "================================================================"
Write-Host ""

Write-Info "Service Information:"
Write-Host "  Service Name: $ServiceName"
Write-Host "  Display Name: $DisplayName"
Write-Host "  Install Location: $InstallDir"
Write-Host "  Data Directory: $DataDir"
Write-Host ""

Write-Info "Useful Commands:"
Write-Host "  Check status:    Get-Service -Name $ServiceName"
Write-Host "  View logs:       Get-EventLog -LogName Application -Source $ServiceName -Newest 50"
Write-Host "  Stop service:    Stop-Service -Name $ServiceName"
Write-Host "  Start service:   Start-Service -Name $ServiceName"
Write-Host "  Restart service: Restart-Service -Name $ServiceName"
Write-Host ""

Write-Info "PowerShell Management:"
Write-Host "  # Check status"
Write-Host "  Get-Service -Name $ServiceName | Format-List"
Write-Host ""
Write-Host "  # View recent logs"
Write-Host "  Get-EventLog -LogName Application -Newest 50 | Where-Object { `$_.Source -like '*$AppName*' }"
Write-Host ""
Write-Host "  # Stop service"
Write-Host "  Stop-Service -Name $ServiceName -Force"
Write-Host ""

Write-Info "Data Access:"
Write-Host "  Data files are saved in: $DataDir"
Write-Host "  You can access these files directly from File Explorer"
Write-Host ""

Write-Info "Configuration:"
Write-Host "  Edit settings: $appSettingsFile"
Write-Host "  After editing, restart the service:"
Write-Host "  Restart-Service -Name $ServiceName"
Write-Host ""

if ($azureConnection) {
    Write-Success "Azure Storage is configured!"
    Write-Host "GPS data will be uploaded to Azure Blob Storage container: $azureContainer"
    Write-Host ""
}

Write-Success "Installation complete! Service is running."
Write-Host ""

