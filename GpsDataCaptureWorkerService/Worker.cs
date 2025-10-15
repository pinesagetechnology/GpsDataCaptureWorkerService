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
        private int _dataCounter;
        private int _invalidDataCounter;

        public Worker(ILogger<Worker> logger,
            IOptions<GpsSettings> settings,
            GpsReaderService gpsReader,
            FileStorageService fileStorage,
            ApiSenderService apiSender)
        {
            _logger = logger;
            _settings = settings.Value;
            _gpsReader = gpsReader;

            if (_settings.Mode == DataMode.SaveToFile || _settings.Mode == DataMode.Both)
            {
                _fileStorage = fileStorage;
            }

            if (_settings.Mode == DataMode.SendToApi || _settings.Mode == DataMode.Both)
            {
                _apiSender = apiSender;
            }
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("GPS Data Capture Worker Service Starting...");
            _logger.LogInformation("Mode: {Mode}", _settings.Mode);
            _logger.LogInformation("Capture Interval: {Interval} seconds", _settings.CaptureIntervalSeconds);

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
            if (_settings.Mode == DataMode.SendToApi || _settings.Mode == DataMode.Both)
            {
                if (string.IsNullOrEmpty(_settings.ApiEndpoint))
                {
                    _logger.LogError("API endpoint not configured but {Mode} mode is enabled!", _settings.Mode);
                    return false;
                }

                _logger.LogInformation("API endpoint configured: {Endpoint}", _settings.ApiEndpoint);
            }

            if (_settings.Mode == DataMode.SaveToFile || _settings.Mode == DataMode.Both)
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
            _logger.LogInformation("GPS Data Capture Service stopped");
        }

        public override async Task StopAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("GPS Data Capture Service stop requested");
            await base.StopAsync(cancellationToken);
        }
    }
}
