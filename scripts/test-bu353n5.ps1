###############################################################################
# GPS Data Capture Worker Service - BU-353N5 GPS Test Script
#
# This script helps you test with the BU-353N5 USB GPS receiver
###############################################################################

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  GPS Data Capture - BU-353N5 USB GPS Test" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""

# Navigate to project directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$projectDir = Join-Path $projectRoot "GpsDataCaptureWorkerService"

Set-Location $projectDir

Write-Host "Testing BU-353N5 USB GPS Receiver" -ForegroundColor Cyan
Write-Host "  Chipset: Prolific PL2303 / SiRF" -ForegroundColor Gray
Write-Host "  Baud Rate: 4800" -ForegroundColor Gray
Write-Host "  Protocol: NMEA 0183" -ForegroundColor Gray
Write-Host ""

# Step 1: Check for COM ports
Write-Host "Step 1: Detecting COM ports..." -ForegroundColor Yellow
try {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -gt 0) {
        Write-Host "✓ Found $($ports.Count) COM port(s):" -ForegroundColor Green
        foreach ($port in $ports) {
            Write-Host "  - $port" -ForegroundColor Cyan
            
            # Try to get more info about the port from WMI
            try {
                $portInfo = Get-WmiObject Win32_PnPEntity | Where-Object { 
                    $_.Caption -match $port -or $_.Name -match $port 
                } | Select-Object -First 1
                
                if ($portInfo) {
                    if ($portInfo.Caption -match "Prolific" -or $portInfo.Caption -match "USB") {
                        Write-Host "    Device: $($portInfo.Caption)" -ForegroundColor Green
                        Write-Host "    ⭐ This looks like your BU-353N5!" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "    Device: $($portInfo.Caption)" -ForegroundColor Gray
                    }
                }
            }
            catch {
                # Silently continue if WMI query fails
            }
        }
        Write-Host ""
    }
    else {
        Write-Host "⚠ No COM ports detected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please check:" -ForegroundColor Red
        Write-Host "  1. BU-353N5 is plugged into USB port" -ForegroundColor White
        Write-Host "  2. Windows has installed the driver (check Device Manager)" -ForegroundColor White
        Write-Host "  3. No other application is using the GPS (close Google Earth, etc.)" -ForegroundColor White
        Write-Host ""
        
        $continue = Read-Host "Continue anyway? (Y/N)"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit 0
        }
    }
}
catch {
    Write-Host "⚠ Could not detect COM ports: $_" -ForegroundColor Yellow
}

# Step 2: Check USB devices
Write-Host "Step 2: Checking USB devices for BU-353N5..." -ForegroundColor Yellow
try {
    $usbDevices = Get-WmiObject Win32_PnPEntity | Where-Object { 
        $_.Caption -match "Prolific" -or 
        $_.Caption -match "GPS" -or 
        $_.Caption -match "BU-353" -or
        ($_.Caption -match "USB" -and $_.Caption -match "Serial")
    }
    
    if ($usbDevices) {
        Write-Host "✓ Found USB GPS device(s):" -ForegroundColor Green
        foreach ($device in $usbDevices) {
            Write-Host "  - $($device.Caption)" -ForegroundColor Cyan
            if ($device.Status -eq "OK") {
                Write-Host "    Status: OK ✓" -ForegroundColor Green
            }
            else {
                Write-Host "    Status: $($device.Status)" -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host "⚠ No USB GPS devices found" -ForegroundColor Yellow
        Write-Host "  The BU-353N5 should appear as 'Prolific USB-to-Serial' or similar" -ForegroundColor Gray
    }
}
catch {
    Write-Host "  Could not query USB devices" -ForegroundColor Gray
}
Write-Host ""

# Step 3: Check data directory
$dataDir = "gps_data_test"
if (Test-Path $dataDir) {
    Write-Host "Step 3: Test data directory exists" -ForegroundColor Yellow
    $fileCount = (Get-ChildItem $dataDir -File -ErrorAction SilentlyContinue).Count
    Write-Host "  Found $fileCount existing file(s)" -ForegroundColor Cyan
    
    if ($fileCount -gt 0) {
        $clearFiles = Read-Host "Clear old test files? (Y/N)"
        if ($clearFiles -eq 'Y' -or $clearFiles -eq 'y') {
            Remove-Item "$dataDir\*" -Force
            Write-Host "  ✓ Cleared old files" -ForegroundColor Green
        }
    }
}
else {
    Write-Host "Step 3: Test data directory will be created" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Show configuration
Write-Host "Step 4: Configuration for BU-353N5" -ForegroundColor Yellow
Write-Host "  Baud Rate: 4800 (default for BU-353N5)" -ForegroundColor Cyan
Write-Host "  Auto-detect: Enabled" -ForegroundColor Cyan
Write-Host "  Data Directory: gps_data_test" -ForegroundColor Cyan
Write-Host "  Save Formats: CSV, NDJSON" -ForegroundColor Cyan
Write-Host ""

# Step 5: Build
Write-Host "Step 5: Building project..." -ForegroundColor Yellow
$buildOutput = dotnet build --nologo -v q 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Build failed" -ForegroundColor Red
    Write-Host $buildOutput
    exit 1
}
Write-Host "✓ Build successful" -ForegroundColor Green
Write-Host ""

# Instructions
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  BU-353N5 GPS Testing Instructions" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""

Write-Host "BEFORE STARTING:" -ForegroundColor Yellow
Write-Host "  1. Place BU-353N5 near a window (GPS needs sky view)" -ForegroundColor White
Write-Host "  2. Wait 30-60 seconds for GPS to acquire satellites" -ForegroundColor White
Write-Host "  3. The blue LED on BU-353N5 should be blinking" -ForegroundColor White
Write-Host "     - Slow blink = searching for satellites" -ForegroundColor Gray
Write-Host "     - Fast blink = GPS fix acquired" -ForegroundColor Gray
Write-Host ""

Write-Host "WHAT WILL HAPPEN:" -ForegroundColor Yellow
Write-Host "  1. Service starts and detects your BU-353N5" -ForegroundColor White
Write-Host "  2. Connects to the GPS device" -ForegroundColor White
Write-Host "  3. Starts receiving NMEA sentences" -ForegroundColor White
Write-Host "  4. Logs GPS data every 5 seconds:" -ForegroundColor White
Write-Host "     - Latitude/Longitude" -ForegroundColor Gray
Write-Host "     - Speed, Course, Altitude" -ForegroundColor Gray
Write-Host "     - Number of satellites" -ForegroundColor Gray
Write-Host "     - Fix quality" -ForegroundColor Gray
Write-Host "  5. Saves data to CSV and NDJSON files" -ForegroundColor White
Write-Host ""

Write-Host "TO STOP:" -ForegroundColor Yellow
Write-Host "  Press Ctrl+C" -ForegroundColor White
Write-Host ""

# Step 6: Run
$response = Read-Host "Ready to test GPS? (Y/N)"
if ($response -eq 'Y' -or $response -eq 'y') {
    Write-Host ""
    Write-Host "Starting GPS Data Capture Service..." -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Blue
    Write-Host ""
    
    # Set development environment
    $env:DOTNET_ENVIRONMENT = "Development"
    
    try {
        # Run the service
        dotnet run
    }
    catch {
        Write-Host ""
        Write-Host "Service stopped" -ForegroundColor Yellow
    }
    finally {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Blue
        Write-Host "  Test Results" -ForegroundColor Blue
        Write-Host "================================================================" -ForegroundColor Blue
        Write-Host ""
        
        # Show generated files
        if (Test-Path $dataDir) {
            $files = Get-ChildItem $dataDir -File | Sort-Object LastWriteTime -Descending
            if ($files.Count -gt 0) {
                Write-Host "✓ GPS data files created:" -ForegroundColor Green
                foreach ($file in $files) {
                    Write-Host "  - $($file.Name) ($([math]::Round($file.Length/1KB, 2)) KB)" -ForegroundColor Cyan
                    
                    # Show first few lines of CSV
                    if ($file.Extension -eq ".csv") {
                        Write-Host "    Preview (first 3 records):" -ForegroundColor Gray
                        $content = Get-Content $file.FullName -TotalCount 4
                        foreach ($line in $content) {
                            if ($line.Length -gt 100) {
                                Write-Host "      $($line.Substring(0, 97))..." -ForegroundColor DarkGray
                            }
                            else {
                                Write-Host "      $line" -ForegroundColor DarkGray
                            }
                        }
                    }
                }
                Write-Host ""
                Write-Host "View data:" -ForegroundColor Yellow
                Write-Host "  notepad $dataDir\*.csv" -ForegroundColor Cyan
                Write-Host "  type $dataDir\*.ndjson" -ForegroundColor Cyan
            }
            else {
                Write-Host "⚠ No files created - GPS may not have acquired a fix" -ForegroundColor Yellow
                Write-Host "  This usually means:" -ForegroundColor Gray
                Write-Host "  - GPS didn't see enough satellites (needs 3+)" -ForegroundColor Gray
                Write-Host "  - BU-353N5 needs to be closer to a window" -ForegroundColor Gray
                Write-Host "  - Cold start can take 30-60 seconds" -ForegroundColor Gray
            }
        }
    }
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
Write-Host "BU-353N5 GPS Test Complete" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Blue

