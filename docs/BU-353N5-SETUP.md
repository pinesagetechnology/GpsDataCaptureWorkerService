# BU-353N5 USB GPS Receiver Setup Guide

This guide provides specific instructions for using the **GlobalSat BU-353N5** USB GPS receiver with the GPS Data Capture Worker Service.

## About the BU-353N5

The BU-353N5 is a popular USB GPS receiver featuring:
- **Chipset**: Prolific PL2303 USB-to-Serial / SiRF Star IV
- **Protocol**: NMEA 0183
- **Baud Rate**: 4800 (default)
- **Update Rate**: 1 Hz (1 time per second)
- **Cold Start**: ~29 seconds
- **Warm Start**: ~1 second
- **Channels**: 48
- **Accuracy**: ~10 meters (with good satellite view)
- **Interface**: USB (appears as COM port)

## Windows Setup

### 1. Driver Installation

Windows usually installs the driver automatically:

1. **Plug in the BU-353N5** to a USB port
2. Wait for Windows to install the driver
3. Check Device Manager:
   - Open Device Manager (Win+X → Device Manager)
   - Look under "Ports (COM & LPT)"
   - You should see: **"Prolific USB-to-Serial Comm Port (COMx)"**
   - Note the COM port number (e.g., COM3)

### 2. LED Indicators

The BU-353N5 has a blue LED that indicates status:
- **Slow blink** (1 time per 2 seconds): Searching for satellites
- **Fast blink** (1 time per second): GPS fix acquired (ready to use)
- **No blink**: No power or not working

### 3. Testing with Windows

#### Quick Test (Automatic Detection)
```powershell
# Run the BU-353N5 specific test script
.\scripts\test-bu353n5.ps1
```

The script will:
- ✅ Auto-detect the BU-353N5 on any COM port
- ✅ Show device information
- ✅ Guide you through testing
- ✅ Show GPS data in real-time

#### Manual Test
```powershell
# Check which COM port
[System.IO.Ports.SerialPort]::GetPortNames()

# Run the service
cd GpsDataCaptureWorkerService
$env:DOTNET_ENVIRONMENT = "Development"
dotnet run
```

### 4. Configuration

The service auto-detects the BU-353N5, but you can also configure it manually:

**File**: `appsettings.json` or `appsettings.Development.json`

```json
{
  "GpsSettings": {
    "BaudRate": 4800,
    "PortName": null,           // null = auto-detect
    "AutoDetectPort": true,     // true = find automatically
    "CaptureIntervalSeconds": 5
  }
}
```

Or specify the COM port directly:
```json
{
  "GpsSettings": {
    "BaudRate": 4800,
    "PortName": "COM3",         // Your specific COM port
    "AutoDetectPort": false,    // Disable auto-detect
    "CaptureIntervalSeconds": 5
  }
}
```

## Linux Setup (Raspberry Pi)

### 1. Connect the Device

1. **Plug in the BU-353N5** to a USB port
2. Check if detected:
   ```bash
   # List USB devices
   lsusb
   # Look for: "Prolific Technology, Inc. PL2303 Serial Port"
   
   # Check serial ports
   ls -l /dev/ttyUSB* /dev/ttyACM*
   # Usually appears as: /dev/ttyUSB0
   ```

### 2. Set Permissions

```bash
# Add your user to dialout group for serial port access
sudo usermod -a -G dialout $USER

# Log out and back in for changes to take effect
```

### 3. Test Raw NMEA Data

```bash
# View raw NMEA sentences (should see $GP... messages)
cat /dev/ttyUSB0

# Or with stty for proper settings
stty -F /dev/ttyUSB0 4800 cs8 -cstopb -parenb
cat /dev/ttyUSB0
```

You should see output like:
```
$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47
$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A
```

### 4. Install the Service

```bash
# Make installation script executable
chmod +x scripts/install-systemd.sh

# Run installation (auto-detects BU-353N5)
sudo scripts/install-systemd.sh

# View logs
sudo journalctl -u gpsdatacapture -f
```

## Placement & Best Practices

### 1. Antenna Placement
- ✅ **Near a window** with clear view of sky
- ✅ **On dashboard** for vehicle use
- ✅ **On roof/balcony** for stationary use
- ❌ **Inside buildings** (weak signal)
- ❌ **Underground** (no signal)
- ❌ **Near metal surfaces** (signal interference)

### 2. Cold Start Tips
When first powered on or after long time off:
- Wait **30-60 seconds** for satellite acquisition
- Blue LED will change from slow to fast blink when ready
- First position may take longer to acquire

### 3. Warm Start
If GPS was recently on (within 2 hours):
- Acquisition time: **~1 second**
- LED should quickly start fast blinking

## Troubleshooting

### Issue: No COM Port Detected (Windows)

**Check Device Manager:**
1. Open Device Manager
2. Look for "Unknown Device" or devices with yellow warning
3. If found, right-click → Update Driver → Search automatically

**Manual Driver Installation:**
1. Download Prolific PL2303 driver from: [https://www.prolific.com.tw/](https://www.prolific.com.tw/)
2. Install the driver
3. Replug the BU-353N5

**Alternative Check:**
```powershell
# PowerShell: List all USB devices
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*USB*" -or $_.FriendlyName -like "*Prolific*"}
```

### Issue: "Access Denied" Error

**Windows:**
- Another program is using the GPS (Google Earth, GPS software, etc.)
- Close all GPS-related programs
- Replug the device

**Linux:**
```bash
# Check if user is in dialout group
groups

# If not listed, add user
sudo usermod -a -G dialout $USER

# Log out and back in
```

### Issue: GPS Not Getting Fix (LED Slow Blink)

**Check Satellite View:**
- Move closer to window
- Check if window has metallic coating (blocks GPS)
- Try outdoors
- Wait 60 seconds minimum

**Check NMEA Output:**
```bash
# Windows (PowerShell)
$port = new-Object System.IO.Ports.SerialPort COM3,4800,None,8,one
$port.Open()
$port.ReadLine()
$port.Close()

# Linux
cat /dev/ttyUSB0
```

Look for `$GPGGA` sentences. The 7th field shows fix quality:
- `0` = Invalid (no fix)
- `1` = GPS fix (good!)
- `2` = DGPS fix (very good!)

Example:
```
$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47
                                          ^ Fix quality (1 = good)
```

### Issue: Service Connects but No Data Saved

**Check Logs:**
```bash
# Linux
sudo journalctl -u gpsdatacapture -f

# Windows (in the console where dotnet run is running)
# Look for: "Skipping invalid GPS data"
```

**Reason:**
The service validates GPS data quality:
- Fix quality must be ≥ 1
- Must have ≥ 3 satellites
- Coordinates must be valid

**Solution:**
- Improve GPS antenna placement
- Wait for better satellite acquisition
- Check for "GPS #{number}" log messages when data is being saved

## Expected Performance

### Typical Results
With good satellite view (near window):
- **Satellite Count**: 6-12 satellites
- **Fix Quality**: 1 (GPS) or 2 (DGPS)
- **Accuracy**: 3-10 meters
- **Update Rate**: Every 1 second from GPS, captured every 5 seconds by default

### Sample Output
```
info: GPS #1: 37.774929°N, 122.419418°W | Speed: 0.0 km/h | Course: 0.0° N | Sats: 8 | Fix: 1
info: GPS #2: 37.774931°N, 122.419420°W | Speed: 0.2 km/h | Course: 45.0° NE | Sats: 9 | Fix: 1
info: GPS #3: 37.774933°N, 122.419422°W | Speed: 1.5 km/h | Course: 47.0° NE | Sats: 9 | Fix: 1
```

## NMEA Sentences Supported

The BU-353N5 outputs these NMEA sentences (all supported by the service):

| Sentence | Description | Used For |
|----------|-------------|----------|
| **$GPGGA** | Global Positioning System Fix Data | Latitude, Longitude, Altitude, Satellites, Fix Quality |
| **$GPRMC** | Recommended Minimum | Latitude, Longitude, Speed, Course, Date/Time |
| **$GPVTG** | Track Made Good and Ground Speed | Speed in km/h, Course |
| $GPGSA | GPS DOP and Active Satellites | Not parsed (future enhancement) |
| $GPGSV | Satellites in View | Not parsed (future enhancement) |

## Resources

### Official Documentation
- [BU-353N5 Product Page](https://www.usglobalsat.com/s-122-bu-353-n5.aspx)
- [Prolific PL2303 Driver](https://www.prolific.com.tw/US/ShowProduct.aspx?p_id=225&pcid=41)

### Useful Tools
**Windows:**
- [GPS Utility](http://www.gpsu.co.uk/) - Test GPS functionality
- [u-center](https://www.u-blox.com/en/product/u-center) - Advanced GPS testing

**Linux:**
- `gpsd` - GPS daemon
- `cgps` - Console GPS viewer
- `gpsmon` - Real-time GPS data monitor

```bash
# Install GPS tools
sudo apt-get install gpsd gpsd-clients

# Test with cgps
cgps -s
```

## Specifications

| Feature | Specification |
|---------|---------------|
| Chipset | SiRF Star IV |
| Frequency | L1, 1575.42 MHz |
| Channels | 48 |
| Position Accuracy | 10m (2D RMS) |
| Velocity Accuracy | 0.1 m/s |
| Time Accuracy | 1μs synchronized to GPS time |
| Cold Start | 29s (average) |
| Warm Start | 1s (average) |
| Hot Start | 1s (average) |
| Reacquisition | 0.1s |
| Sensitivity | -159 dBm |
| Update Rate | 1 Hz (default) |
| Protocol | NMEA 0183 v3.01 |
| Baud Rate | 4800 bps (default) |
| Interface | USB 2.0 |
| Cable Length | 1.5m (5 feet) |
| Operating Temp | -40°C to +85°C |
| Power | 5V DC via USB, <100mA |

## Support

If you encounter issues with the BU-353N5:
1. ✅ Check this troubleshooting guide
2. ✅ Review service logs
3. ✅ Test with raw NMEA output
4. ✅ Verify driver installation
5. ✅ Check satellite view/placement

