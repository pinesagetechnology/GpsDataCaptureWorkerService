using GpsDataCaptureWorkerService.Models;
using GpsDataCaptureWorkerService.Services;
using Microsoft.Extensions.Options;

namespace GpsDataCaptureWorkerService
{
    public class Worker : BackgroundService
    {
        private readonly ILogger<Worker> _logger;
        private readonly GpsSettings _settings;
        private readonly GpsReaderService _gpsReader;
        private readonly FileStorageService? _fileStorage;
        private readonly ApiSenderService? _apiSender;
        private readonly AzureStorageService? _azureStorage;
        private int _dataCounter;
        private int _invalidDataCounter;
        private int _stationaryDataCounter;
        private GpsData? _lastSavedPosition;

        public Worker(ILogger<Worker> logger,
            IOptions<GpsSettings> settings,
            GpsReaderService gpsReader,
            FileStorageService fileStorage,
            ApiSenderService apiSender,
            AzureStorageService azureStorage)
        {
            _logger = logger;
            _settings = settings.Value;
            _gpsReader = gpsReader;

            // Initialize services based on mode
            if (_settings.Mode == DataMode.SaveToFile || 
                _settings.Mode == DataMode.FileAndApi || 
                _settings.Mode == DataMode.FileAndAzure || 
                _settings.Mode == DataMode.All)
            {
                _fileStorage = fileStorage;
            }

            if (_settings.Mode == DataMode.SendToApi || 
                _settings.Mode == DataMode.FileAndApi || 
                _settings.Mode == DataMode.ApiAndAzure || 
                _settings.Mode == DataMode.All)
            {
                _apiSender = apiSender;
            }

            if (_settings.Mode == DataMode.SendToAzureStorage || 
                _settings.Mode == DataMode.FileAndAzure || 
                _settings.Mode == DataMode.ApiAndAzure || 
                _settings.Mode == DataMode.All)
            {
                _azureStorage = azureStorage;
            }
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("GPS Data Capture Worker Service Starting...");
            _logger.LogInformation("Mode: {Mode}", _settings.Mode);
            _logger.LogInformation("Capture Interval: {Interval} seconds", _settings.CaptureIntervalSeconds);
            _logger.LogInformation("Minimum Movement Distance: {Distance} meters", _settings.MinimumMovementDistanceMeters);

            // Validate configuration
            if (!ValidateConfiguration())
            {
                _logger.LogError("Invalid configuration. Service stopping.");
                return;
            }

            // Subscribe to GPS data events
            _gpsReader.DataReceived += OnGpsDataReceived;

            try
            {
                // Connect to GPS with retry logic
                if (!await ConnectWithRetryAsync(stoppingToken))
                {
                    _logger.LogError("Failed to connect to GPS device after multiple attempts. Service stopping.");
                    return;
                }

                _logger.LogInformation("GPS Data Capture Service is running");

                // Start capturing GPS data
                await _gpsReader.StartCapture(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("GPS Data Capture Service is stopping due to cancellation");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Fatal error in GPS Data Capture Service");
                throw;
            }
            finally
            {
                await CleanupAsync();
            }
        }

        private bool ValidateConfiguration()
        {
            // Validate API settings
            if (_settings.Mode == DataMode.SendToApi || 
                _settings.Mode == DataMode.FileAndApi || 
                _settings.Mode == DataMode.ApiAndAzure || 
                _settings.Mode == DataMode.All)
            {
                if (string.IsNullOrEmpty(_settings.ApiEndpoint))
                {
                    _logger.LogError("API endpoint not configured but {Mode} mode is enabled!", _settings.Mode);
                    return false;
                }

                _logger.LogInformation("API endpoint configured: {Endpoint}", _settings.ApiEndpoint);
            }

            // Validate Azure Storage settings
            if (_settings.Mode == DataMode.SendToAzureStorage || 
                _settings.Mode == DataMode.FileAndAzure || 
                _settings.Mode == DataMode.ApiAndAzure || 
                _settings.Mode == DataMode.All)
            {
                if (string.IsNullOrEmpty(_settings.AzureStorageConnectionString))
                {
                    _logger.LogError("Azure Storage connection string not configured but {Mode} mode is enabled!", _settings.Mode);
                    return false;
                }

                _logger.LogInformation("Azure Storage configured. Container: {Container}", 
                    _settings.AzureStorageContainerName);
            }

            // Validate File Storage settings
            if (_settings.Mode == DataMode.SaveToFile || 
                _settings.Mode == DataMode.FileAndApi || 
                _settings.Mode == DataMode.FileAndAzure || 
                _settings.Mode == DataMode.All)
            {
                _logger.LogInformation("File storage enabled. Formats: {Formats}",
                    string.Join(", ", _settings.SaveFormats));
            }

            return true;
        }

        private async Task<bool> ConnectWithRetryAsync(CancellationToken cancellationToken)
        {
            const int maxAttempts = 5;
            const int delaySeconds = 10;

            for (int attempt = 1; attempt <= maxAttempts; attempt++)
            {
                if (cancellationToken.IsCancellationRequested)
                    return false;

                _logger.LogInformation("Attempting to connect to GPS device (attempt {Attempt}/{Max})...",
                    attempt, maxAttempts);

                if (_gpsReader.Connect())
                {
                    _logger.LogInformation("Successfully connected to GPS device");
                    return true;
                }

                if (attempt < maxAttempts)
                {
                    _logger.LogWarning("Failed to connect. Retrying in {Delay} seconds...", delaySeconds);
                    await Task.Delay(TimeSpan.FromSeconds(delaySeconds), cancellationToken);
                }
            }

            return false;
        }

        private void OnGpsDataReceived(object? sender, GpsData data)
        {
            // Fire and forget - process asynchronously without blocking
            _ = Task.Run(async () =>
            {
                try
                {
                    // Validate GPS data quality before processing
                    if (!IsValidGpsData(data))
                    {
                        Interlocked.Increment(ref _invalidDataCounter);
                        _logger.LogDebug("Skipping invalid GPS data: Fix Quality={Fix}, Sats={Sats}", 
                            data.FixQuality ?? 0, data.Satellites ?? 0);
                        return;
                    }

                    // Check if vehicle has moved enough to save/send data
                    if (_lastSavedPosition != null)
                    {
                        double distanceMeters = CalculateDistance(
                            _lastSavedPosition.Latitude!.Value,
                            _lastSavedPosition.Longitude!.Value,
                            data.Latitude!.Value,
                            data.Longitude!.Value);

                        if (distanceMeters < _settings.MinimumMovementDistanceMeters)
                        {
                            Interlocked.Increment(ref _stationaryDataCounter);
                            _logger.LogDebug(
                                "Vehicle stationary. Distance: {Distance:F2}m (threshold: {Threshold}m). Skipping save/send.",
                                distanceMeters, _settings.MinimumMovementDistanceMeters);
                            return;
                        }

                        _logger.LogDebug("Vehicle moved {Distance:F2} meters. Saving/sending GPS data.", distanceMeters);
                    }

                    Interlocked.Increment(ref _dataCounter);

                    _logger.LogInformation(
                        "GPS #{Count}: {Lat:F6}�{LatDir}, {Lon:F6}�{LonDir} | " +
                        "Speed: {Speed:F1} km/h | Course: {Course:F1}� {Dir} | Sats: {Sats} | Fix: {Fix}",
                        _dataCounter,
                        Math.Abs(data.Latitude ?? 0), (data.Latitude ?? 0) >= 0 ? "N" : "S",
                        Math.Abs(data.Longitude ?? 0), (data.Longitude ?? 0) >= 0 ? "E" : "W",
                        data.SpeedKmh ?? 0,
                        data.Course ?? 0, data.CourseDirection ?? "N/A",
                        data.Satellites ?? 0,
                        data.FixQuality ?? 0);

                    // Save to file if enabled
                    if (_fileStorage != null)
                    {
                        await _fileStorage.SaveAsync(data);
                    }

                    // Send to API if enabled
                    if (_apiSender != null)
                    {
                        _apiSender.QueueData(data);
                    }

                    // Send to Azure Storage if enabled
                    if (_azureStorage != null)
                    {
                        _azureStorage.QueueData(data);
                    }

                    // Update last saved position
                    _lastSavedPosition = CloneGpsData(data);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error processing GPS data");
                }
            });
        }

        private bool IsValidGpsData(GpsData data)
        {
            // Must have valid coordinates
            if (!data.Latitude.HasValue || !data.Longitude.HasValue)
                return false;

            // Fix quality: 0=invalid, 1=GPS fix, 2=DGPS fix, etc.
            // Accept quality >= 1
            if (data.FixQuality.HasValue && data.FixQuality.Value < 1)
                return false;

            // Should have at least some satellites (typically need 4+ for a fix)
            if (data.Satellites.HasValue && data.Satellites.Value < 3)
                return false;

            // Validate coordinate ranges
            if (Math.Abs(data.Latitude.Value) > 90 || Math.Abs(data.Longitude.Value) > 180)
                return false;

            return true;
        }

        /// <summary>
        /// Calculates the distance between two GPS coordinates using the Haversine formula.
        /// Returns distance in meters.
        /// </summary>
        private double CalculateDistance(double lat1, double lon1, double lat2, double lon2)
        {
            const double earthRadiusMeters = 6371000; // Earth's radius in meters

            double dLat = ToRadians(lat2 - lat1);
            double dLon = ToRadians(lon2 - lon1);

            double a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                       Math.Cos(ToRadians(lat1)) * Math.Cos(ToRadians(lat2)) *
                       Math.Sin(dLon / 2) * Math.Sin(dLon / 2);

            double c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
            return earthRadiusMeters * c;
        }

        private double ToRadians(double degrees)
        {
            return degrees * Math.PI / 180.0;
        }

        private GpsData CloneGpsData(GpsData source)
        {
            return new GpsData
            {
                Timestamp = source.Timestamp,
                Latitude = source.Latitude,
                Longitude = source.Longitude,
                Altitude = source.Altitude,
                SpeedKmh = source.SpeedKmh,
                SpeedMph = source.SpeedMph,
                Course = source.Course,
                CourseDirection = source.CourseDirection,
                Satellites = source.Satellites,
                FixQuality = source.FixQuality,
                Hdop = source.Hdop,
                Status = source.Status,
                DeviceId = source.DeviceId
            };
        }

        private async Task CleanupAsync()
        {
            _logger.LogInformation("Cleaning up GPS Data Capture Service...");

            _gpsReader.DataReceived -= OnGpsDataReceived;
            _gpsReader.Dispose();

            if (_apiSender != null)
            {
                _logger.LogInformation("Flushing remaining API data...");
                await _apiSender.FlushAsync();
                _apiSender.Dispose();
            }

            if (_azureStorage != null)
            {
                _logger.LogInformation("Flushing remaining Azure Storage data...");
                await _azureStorage.FlushAsync();
                _azureStorage.Dispose();
            }

            if (_fileStorage != null)
            {
                _fileStorage.PrintSummary();
                
                // Dispose FileStorageService if it implements IDisposable
                if (_fileStorage is IDisposable disposable)
                {
                    disposable.Dispose();
                }
            }

            _logger.LogInformation("=== GPS Capture Summary ===");
            _logger.LogInformation("Valid GPS data points captured: {Count}", _dataCounter);
            _logger.LogInformation("Invalid GPS data points skipped: {Count}", _invalidDataCounter);
            _logger.LogInformation("Stationary GPS data points skipped: {Count}", _stationaryDataCounter);
            _logger.LogInformation("GPS Data Capture Service stopped");
        }

        public override async Task StopAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("GPS Data Capture Service stop requested");
            await base.StopAsync(cancellationToken);
        }
    }
}
