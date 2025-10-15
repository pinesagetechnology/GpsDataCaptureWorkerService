# GPS Data Capture Worker Service

A cross-platform .NET 8.0 worker service for capturing GPS data from NMEA-compatible devices, designed to run on IoT devices like Raspberry Pi and Windows systems.

## Features

### 🛰️ GPS Capture
- **NMEA Sentence Parsing**: Supports RMC, GGA, and VTG sentences
- **Auto Port Detection**: Automatically detects GPS devices on Windows, Linux, and macOS
- **Configurable Baud Rate**: Default 4800, customizable
- **Retry Logic**: Automatic reconnection with configurable retry attempts
- **Data Validation**: Validates GPS fix quality and satellite count before saving

### 💾 Data Storage
- **Multiple Formats**: 
  - **CSV** - Standard comma-separated values
  - **JSON** - Pretty-printed JSON array (not recommended for long-running captures)
  - **NDJSON** - Newline-delimited JSON (recommended for IoT/streaming)
- **Daily File Rotation**: Files are named with date stamps (e.g., `gps_data_20241014.csv`)
- **Thread-Safe**: Concurrent writes are safely handled
- **Configurable Directory**: Store data wherever you need

### 🌐 API Integration
- **Batch Processing**: Configurable batch sizes to reduce API calls
- **Retry with Exponential Backoff**: Automatic retry on failures
- **Queue-Based**: Prevents data loss during network issues
- **Configurable Timeout**: Set API timeout and retry attempts

### 🔧 Operating Modes
- `SaveToFile` - Save GPS data to local files only
- `SendToApi` - Send GPS data to API endpoint only
- `Both` - Save locally and send to API

### 🖥️ Platform Support
- **Windows**: Runs as a Windows Service
- **Linux**: Runs as a Systemd service
- **Raspberry Pi**: Optimized for IoT devices
- **macOS**: Development and testing support

## Quick Start

### Prerequisites
- .NET 8.0 SDK or Runtime
- GPS device with USB connection (NMEA-compatible)
- Serial port access permissions (Linux/macOS may require)

### Configuration

Edit `appsettings.json`:

```json
{
  "GpsSettings": {
    "Mode": "SaveToFile",
    "BaudRate": 4800,
    "PortName": null,
    "AutoDetectPort": true,
    "CaptureIntervalSeconds": 5,
    "SaveFormats": [ "csv", "ndjson" ],
    "DataDirectory": "gps_data",
    "ApiEndpoint": "https://api.example.com/gps/data",
    "ApiKey": "",
    "ApiTimeoutSeconds": 30,
    "RetryAttempts": 3,
    "BatchSize": 10,
    "EnableLogging": true
  }
}
```

#### Configuration Options

| Setting | Type | Description | Default |
|---------|------|-------------|---------|
| `Mode` | enum | Operating mode: `SaveToFile`, `SendToApi`, `Both` | `SaveToFile` |
| `BaudRate` | int | Serial port baud rate | `4800` |
| `PortName` | string | Specific port name (e.g., `COM3`, `/dev/ttyUSB0`) | `null` (auto-detect) |
| `AutoDetectPort` | bool | Automatically detect GPS port | `true` |
| `CaptureIntervalSeconds` | int | Seconds between data captures | `5` |
| `SaveFormats` | array | File formats: `csv`, `json`, `ndjson` | `["csv", "ndjson"]` |
| `DataDirectory` | string | Directory for saved files | `gps_data` |
| `ApiEndpoint` | string | API endpoint URL | - |
| `ApiKey` | string | API authentication key | - |
| `ApiTimeoutSeconds` | int | API request timeout | `30` |
| `RetryAttempts` | int | Number of retry attempts for API | `3` |
| `BatchSize` | int | Number of records per API batch | `10` |

### Running the Service

#### Development (Windows/Linux/macOS)
```bash
cd GpsDataCaptureWorkerService
dotnet run
```

#### Windows Service Installation
```powershell
# Build and publish
dotnet publish -c Release -o C:\Services\GpsDataCapture

# Install as Windows Service
sc create GpsDataCapture binPath="C:\Services\GpsDataCapture\GpsDataCaptureWorkerService.exe"
sc start GpsDataCapture

# View service status
sc query GpsDataCapture

# Stop and remove
sc stop GpsDataCapture
sc delete GpsDataCapture
```

#### Linux/Raspberry Pi Systemd Service

1. Publish the application:
```bash
dotnet publish -c Release -r linux-arm64 --self-contained -o /opt/gpsdatacapture
```

2. Create systemd service file `/etc/systemd/system/gpsdatacapture.service`:
```ini
[Unit]
Description=GPS Data Capture Worker Service
After=network.target

[Service]
Type=notify
WorkingDirectory=/opt/gpsdatacapture
ExecStart=/opt/gpsdatacapture/GpsDataCaptureWorkerService
Restart=always
RestartSec=10
User=pi
Environment=DOTNET_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
```

3. Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable gpsdatacapture
sudo systemctl start gpsdatacapture
sudo systemctl status gpsdatacapture
```

4. View logs:
```bash
sudo journalctl -u gpsdatacapture -f
```

### Linux Serial Port Permissions

On Linux, you may need to add your user to the `dialout` group:
```bash
sudo usermod -a -G dialout $USER
# Log out and log back in for changes to take effect
```

## Architecture

### Components

```
┌─────────────────────────────────────────┐
│           Worker Service                │
│  (Background Service Coordinator)       │
└─────────────┬───────────────────────────┘
              │
              ├──> GpsReaderService
              │    ├─> GpsPortDetector
              │    └─> NmeaSentenceParser
              │
              ├──> FileStorageService
              │    ├─> CSV Writer
              │    ├─> JSON Writer
              │    └─> NDJSON Writer
              │
              └──> ApiSenderService
                   ├─> Batch Queue
                   └─> HttpClient
```

### Data Flow

1. **GPS Reader** continuously reads NMEA sentences from serial port
2. **Parser** validates and parses GPS sentences (RMC, GGA, VTG)
3. **Validator** checks GPS fix quality, satellite count, coordinate validity
4. **Worker** receives valid GPS data via event
5. **Storage** saves to configured file formats (thread-safe)
6. **API Sender** queues and batches data for API transmission

## GPS Data Format

### Captured Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | DateTime | UTC timestamp when data was captured |
| `latitude` | double | Latitude in decimal degrees |
| `longitude` | double | Longitude in decimal degrees |
| `altitude` | double? | Altitude in meters |
| `speed_kmh` | double? | Speed in kilometers per hour |
| `speed_mph` | double? | Speed in miles per hour |
| `course` | double? | Course in degrees (0-360) |
| `course_direction` | string | Direction (N, NE, E, SE, S, SW, W, NW, etc.) |
| `satellites` | int? | Number of satellites in view |
| `fix_quality` | int? | GPS fix quality (0=invalid, 1=GPS, 2=DGPS) |
| `hdop` | double? | Horizontal dilution of precision |
| `status` | string | GPS status (A=Active, V=Void) |
| `device_id` | string | Device identifier (machine name) |

### NDJSON Example
```json
{"timestamp":"2024-10-14T12:30:45Z","latitude":37.7749,"longitude":-122.4194,"altitude":10.5,"speed_kmh":25.3,"satellites":8,"fix_quality":1,"device_id":"raspberrypi"}
{"timestamp":"2024-10-14T12:30:50Z","latitude":37.7750,"longitude":-122.4195,"altitude":10.8,"speed_kmh":26.1,"satellites":8,"fix_quality":1,"device_id":"raspberrypi"}
```

## Data Validation

The service validates GPS data before saving:

- ✅ Must have valid latitude and longitude
- ✅ Fix quality must be ≥ 1 (valid GPS fix)
- ✅ Must have at least 3 satellites
- ✅ Coordinates must be in valid ranges (-90 to 90 lat, -180 to 180 lon)

Invalid data is logged but not saved.

## Troubleshooting

### GPS Not Detected

**Windows:**
```powershell
# List available COM ports
mode
# Or check Device Manager
```

**Linux/Raspberry Pi:**
```bash
# List USB devices
ls -l /dev/ttyUSB* /dev/ttyACM*

# Check if device is detected
dmesg | grep tty

# Test serial port
sudo cat /dev/ttyUSB0  # Should show NMEA sentences
```

### No GPS Fix

- Ensure GPS antenna has clear view of sky
- Wait 30-60 seconds for cold start acquisition
- Check that GPS device is powered on
- Verify baud rate matches your GPS device (usually 4800 or 9600)

### Permission Denied (Linux)

```bash
# Add user to dialout group
sudo usermod -a -G dialout $USER

# Or run with sudo (not recommended for production)
sudo dotnet run
```

### High Memory Usage with JSON Format

If using `json` format for long-running captures, memory usage will grow as the entire file is read/written on each save. Use `ndjson` format instead:

```json
"SaveFormats": [ "csv", "ndjson" ]
```

## Performance Considerations

### Recommended File Formats

- **CSV**: Best for Excel/spreadsheet analysis, moderate performance
- **NDJSON**: Best for IoT devices and streaming, excellent performance, easy to process line-by-line
- **JSON**: Use only for short captures or testing

### Capture Interval

- **1-5 seconds**: Standard tracking
- **10-30 seconds**: Battery-conscious IoT deployments
- **< 1 second**: High-frequency tracking (e.g., vehicle racing)

### API Batch Size

- **Small (1-5)**: Real-time updates, higher API load
- **Medium (10-20)**: Balanced approach
- **Large (50-100)**: Reduced API calls, higher latency

## Dependencies

- .NET 8.0
- CsvHelper - CSV file generation
- System.IO.Ports - Serial port communication
- Microsoft.Extensions.Hosting - Worker service framework

## License

This project is provided as-is for GPS data capture applications.

## Contributing

Contributions are welcome! Please ensure:
- Code follows existing patterns
- All changes are tested on target platforms
- Documentation is updated

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review logs in `gps_data` directory
3. Verify GPS device compatibility (NMEA 0183 standard)

