###############################################################################
# GPS Data Capture Worker Service - Windows Test Script
#
# This script helps you test the service on Windows
###############################################################################

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  GPS Data Capture Worker Service - Windows Test" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""

# Navigate to project directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$projectDir = Join-Path $projectRoot "GpsDataCaptureWorkerService"

Set-Location $projectDir

Write-Host "Project Directory: $projectDir" -ForegroundColor Yellow
Write-Host ""

# Check for COM ports
Write-Host "Step 1: Detecting available COM ports..." -ForegroundColor Yellow
try {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -gt 0) {
        Write-Host "✓ Found $($ports.Count) COM port(s):" -ForegroundColor Green
        foreach ($port in $ports) {
            Write-Host "  - $port" -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "Do you have a GPS device connected to any of these ports?" -ForegroundColor Yellow
        Write-Host "If yes, update appsettings.Development.json with the correct port number." -ForegroundColor Yellow
    }
    else {
        Write-Host "⚠ No COM ports detected" -ForegroundColor Yellow
        Write-Host "  The service will fail to connect to GPS device" -ForegroundColor Yellow
        Write-Host "  This is normal if you don't have a GPS device connected" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠ Could not detect COM ports" -ForegroundColor Yellow
}
Write-Host ""

# Check if data directory exists
$dataDir = "gps_data_test"
if (Test-Path $dataDir) {
    Write-Host "Step 2: Test data directory exists" -ForegroundColor Yellow
    $fileCount = (Get-ChildItem $dataDir -File).Count
    Write-Host "  Found $fileCount existing file(s)" -ForegroundColor Cyan
}
else {
    Write-Host "Step 2: Test data directory will be created" -ForegroundColor Yellow
}
Write-Host ""

# Show configuration
Write-Host "Step 3: Current Configuration (Development)" -ForegroundColor Yellow
if (Test-Path "appsettings.Development.json") {
    $config = Get-Content "appsettings.Development.json" | ConvertFrom-Json
    Write-Host "  Mode: $($config.GpsSettings.Mode)" -ForegroundColor Cyan
    Write-Host "  Data Directory: $($config.GpsSettings.DataDirectory)" -ForegroundColor Cyan
    Write-Host "  Auto Detect Port: $($config.GpsSettings.AutoDetectPort)" -ForegroundColor Cyan
    Write-Host "  Port Name: $($config.GpsSettings.PortName)" -ForegroundColor Cyan
    Write-Host "  Save Formats: $($config.GpsSettings.SaveFormats -join ', ')" -ForegroundColor Cyan
}
Write-Host ""

# Build the project
Write-Host "Step 4: Building project..." -ForegroundColor Yellow
dotnet build --nologo -v q
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Build failed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Build successful" -ForegroundColor Green
Write-Host ""

# Ask to run
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  Ready to Test!" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""
Write-Host "What you'll see:" -ForegroundColor Yellow
Write-Host "  1. Service will start and load configuration" -ForegroundColor White
Write-Host "  2. It will attempt to detect/connect to GPS device" -ForegroundColor White
Write-Host "  3. Without a GPS device, it will retry 5 times and stop" -ForegroundColor White
Write-Host "  4. Press Ctrl+C to stop the service at any time" -ForegroundColor White
Write-Host ""

$response = Read-Host "Run the service now? (Y/N)"
if ($response -eq 'Y' -or $response -eq 'y') {
    Write-Host ""
    Write-Host "Starting service... (Press Ctrl+C to stop)" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Blue
    Write-Host ""
    
    # Set development environment
    $env:DOTNET_ENVIRONMENT = "Development"
    
    # Run the service
    dotnet run
}
else {
    Write-Host ""
    Write-Host "To run manually:" -ForegroundColor Yellow
    Write-Host "  cd GpsDataCaptureWorkerService" -ForegroundColor Cyan
    Write-Host "  `$env:DOTNET_ENVIRONMENT = 'Development'" -ForegroundColor Cyan
    Write-Host "  dotnet run" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "Test Complete" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Blue

