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
    Write-Host "Please install .NET 9.0 SDK from: https://dotnet.microsoft.com/download"
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

# Step 4: Configure API Endpoint (if needed)
Write-Warning "Step 4: API Endpoint Configuration"
Write-Host ""
Write-Host "Do you want to configure an API endpoint to send GPS data?"
Write-Host "This allows the service to automatically send GPS data to your API."
Write-Host ""

$configureApi = Read-Host "Configure API Endpoint? (y/N)"

$apiEndpoint = ""
$apiKey = ""

if ($configureApi -match '^[Yy]$') {
    Write-Host ""
    Write-Info "API Configuration:"
    Write-Host ""
    
    # Prompt for API endpoint
    Write-Host "Enter your API endpoint URL:"
    Write-Host "(Example: https://api.example.com/gps/data)"
    $apiEndpoint = Read-Host "API Endpoint"
    
    # Prompt for API key (optional)
    Write-Host ""
    Write-Host "Enter your API key (leave empty if not required):"
    $apiKey = Read-Host "API Key"
    
    Write-Host ""
    Write-Success "✓ API will be configured with endpoint: $apiEndpoint"
} else {
    Write-Info "ℹ Skipping API configuration"
}
Write-Host ""

# Step 5: Configure Azure Storage (if needed)
Write-Warning "Step 5: Azure Storage Configuration"
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
    Write-Host "(Format: DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net)"
    Write-Host ""
    $azureConnection = Read-Host "Azure Storage Connection String"
    
    # Validate connection string is not empty
    if ([string]::IsNullOrWhiteSpace($azureConnection)) {
        Write-Warning "⚠ Azure Storage connection string is empty. Skipping Azure Storage configuration."
        $azureConnection = ""
    } else {
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
    }
} else {
    Write-Info "ℹ Skipping Azure Storage configuration"
}
Write-Host ""

# Step 5b: Configure PostgreSQL (if needed)
Write-Warning "Step 5b: PostgreSQL Configuration"
Write-Host ""
Write-Host "Do you want to configure PostgreSQL for GPS data storage?"
Write-Host "This allows the service to automatically save GPS data to PostgreSQL database."
Write-Host ""

$configurePostgres = Read-Host "Configure PostgreSQL? (y/N)"

$postgresConnection = ""
$postgresStoreRawData = $false

if ($configurePostgres -match '^[Yy]$') {
    Write-Host ""
    Write-Info "PostgreSQL Configuration:"
    Write-Host ""
    
    # Prompt for connection string
    Write-Host "Enter your PostgreSQL connection string:"
    Write-Host "(Format: Host=localhost;Port=5432;Database=iot_gateway;Username=user;Password=pass;Pooling=true;Minimum Pool Size=1;Maximum Pool Size=10;)"
    Write-Host ""
    $postgresConnection = Read-Host "PostgreSQL Connection String"
    
    # Validate connection string is not empty
    if ([string]::IsNullOrWhiteSpace($postgresConnection)) {
        Write-Warning "⚠ PostgreSQL connection string is empty. Skipping PostgreSQL configuration."
        $postgresConnection = ""
    } else {
        # Prompt for raw data storage
        Write-Host ""
        Write-Host "Do you want to store raw GPS data as JSON in the database?"
        Write-Host "(This stores the complete GPS data as JSON in the raw_data column)"
        $storeRawInput = Read-Host "Store Raw Data? (y/N) [N]"
        
        if ($storeRawInput -match '^[Yy]$') {
            $postgresStoreRawData = $true
        }
        
        Write-Host ""
        Write-Success "✓ PostgreSQL will be configured"
        if ($postgresStoreRawData) {
            Write-Success "✓ Raw data storage enabled"
        }
    }
} else {
    Write-Info "ℹ Skipping PostgreSQL configuration"
}
Write-Host ""

# Step 6: Update appsettings.json
Write-Warning "Step 6: Configuring application settings..."
$appSettingsFile = Join-Path $InstallDir "appsettings.json"

if (Test-Path $appSettingsFile) {
    # Backup original
    Copy-Item $appSettingsFile "$appSettingsFile.bak" -Force
    
    # Read appsettings.json
    $appSettings = Get-Content $appSettingsFile -Raw | ConvertFrom-Json
    
    # Update DataDirectory
    $appSettings.GpsSettings.DataDirectory = $DataDir
    Write-Success "✓ Updated DataDirectory to: $DataDir"
    
    # Update API settings if configured
    if ($apiEndpoint) {
        $appSettings.GpsSettings.ApiEndpoint = $apiEndpoint
        Write-Success "✓ Updated API endpoint to: $apiEndpoint"
        
        if ($apiKey) {
            $appSettings.GpsSettings.ApiKey = $apiKey
            Write-Success "✓ Updated API key"
        }
    }
    
    # Update Azure Storage settings if configured
    if ($azureConnection) {
        $appSettings.GpsSettings.AzureStorageConnectionString = $azureConnection
        $appSettings.GpsSettings.AzureStorageContainerName = $azureContainer
        Write-Success "✓ Updated Azure Storage connection string"
        Write-Success "✓ Updated Azure Storage container name to: $azureContainer"
    }
    
    # Update PostgreSQL settings if configured
    if ($postgresConnection) {
        $appSettings.GpsSettings.PostgresConnectionString = $postgresConnection
        $appSettings.GpsSettings.PostgresStoreRawData = $postgresStoreRawData
        Write-Success "✓ Updated PostgreSQL connection string"
        Write-Success "✓ Updated PostgreSQL raw data storage: $postgresStoreRawData"
    }
    
    # Determine the operating mode based on configuration
    $modeComponents = @()
    if ($apiEndpoint) { $modeComponents += "Api" }
    if ($azureConnection) { $modeComponents += "Azure" }
    if ($postgresConnection) { $modeComponents += "Postgres" }
    
    if ($modeComponents.Count -eq 0) {
        $appSettings.GpsSettings.Mode = "SaveToFile"
        Write-Success "✓ Mode set to: SaveToFile"
    } elseif ($modeComponents.Count -eq 1) {
        if ($apiEndpoint) {
            $appSettings.GpsSettings.Mode = "SendToApi"
            Write-Success "✓ Mode set to: SendToApi"
        } elseif ($azureConnection) {
            $appSettings.GpsSettings.Mode = "SendToAzureStorage"
            Write-Success "✓ Mode set to: SendToAzureStorage"
        } elseif ($postgresConnection) {
            $appSettings.GpsSettings.Mode = "SaveToPostgres"
            Write-Success "✓ Mode set to: SaveToPostgres"
        }
    } else {
        # Multiple modes - use appropriate combined mode
        $hasFile = $false  # File mode is default, not explicitly requested
        $modeString = [string]::Join("", $modeComponents)
        
        # Map to enum values
        switch ($modeString) {
            "ApiAzure" { $appSettings.GpsSettings.Mode = "ApiAndAzure" }
            "ApiPostgres" { $appSettings.GpsSettings.Mode = "ApiAndPostgres" }
            "AzurePostgres" { $appSettings.GpsSettings.Mode = "AzureAndPostgres" }
            "ApiAzurePostgres" { $appSettings.GpsSettings.Mode = "ApiAzureAndPostgres" }
            default { $appSettings.GpsSettings.Mode = "All" }
        }
        Write-Success "✓ Mode set to: $($appSettings.GpsSettings.Mode)"
    }
    
    # Ensure MinimumMovementDistanceMeters is set (default: 10.0)
    if (-not $appSettings.GpsSettings.MinimumMovementDistanceMeters) {
        $appSettings.GpsSettings | Add-Member -MemberType NoteProperty -Name "MinimumMovementDistanceMeters" -Value 10.0 -Force
    }
    Write-Success "✓ Minimum Movement Distance: $($appSettings.GpsSettings.MinimumMovementDistanceMeters) meters"
    
    # Save updated appsettings.json
    $appSettings | ConvertTo-Json -Depth 10 | Set-Content $appSettingsFile -Encoding UTF8
    Write-Info "ℹ Backup saved: $appSettingsFile.bak"
} else {
    Write-Warning "⚠ Warning: appsettings.json not found"
}
Write-Host ""

# Step 7: Create Windows Service
Write-Warning "Step 7: Creating Windows Service..."
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

# Step 8: Start the service
Write-Warning "Step 8: Starting service..."
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

# Step 9: Show service status
Write-Warning "Step 9: Service Status"
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

if ($apiEndpoint) {
    Write-Success "API is configured!"
    Write-Host "GPS data will be sent to: $apiEndpoint"
    Write-Host ""
}

if ($azureConnection) {
    Write-Success "Azure Storage is configured!"
    Write-Host "GPS data will be uploaded to Azure Blob Storage container: $azureContainer"
    Write-Host ""
}

Write-Success "Installation complete! Service is running."
Write-Host ""

