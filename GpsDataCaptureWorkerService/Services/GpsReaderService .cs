using GpsDataCaptureWorkerService.GPSProcessing;
using GpsDataCaptureWorkerService.Models;
using Microsoft.Extensions.Options;
using System.IO.Ports;

namespace GpsDataCaptureWorkerService.Services
{
    public interface IGpsReaderService
    {
        public bool Connect();
        Task StartCapture(CancellationToken cancellationToken = default);
        void Stop();
    }

    public class GpsReaderService : IGpsReaderService, IDisposable
    {
        private readonly GpsSettings _settings;
        private readonly ILogger<GpsReaderService> _logger;
        private readonly GpsPortDetector _portDetector;
        private SerialPort? _serialPort;
        private bool _isRunning;

        public event EventHandler<GpsData>? DataReceived;

        public GpsReaderService(
            IOptions<GpsSettings> settings,
            ILogger<GpsReaderService> logger,
            GpsPortDetector portDetector)
        {
            _settings = settings.Value;
            _logger = logger;
            _portDetector = portDetector;
        }

        public bool Connect()
        {
            try
            {
                var portName = _settings.PortName;

                if (_settings.AutoDetectPort || string.IsNullOrEmpty(portName))
                {
                    portName = _portDetector.DetectGpsPort();
                    if (string.IsNullOrEmpty(portName))
                    {
                        _logger.LogError("Failed to detect GPS port");
                        return false;
                    }
                }

                _logger.LogInformation("Connecting to GPS on {Port} at {BaudRate} baud",
                    portName, _settings.BaudRate);

                _serialPort = new SerialPort(portName, _settings.BaudRate, Parity.None, 8, StopBits.One)
                {
                    ReadTimeout = 5000,
                    NewLine = "\r\n"
                };

                _serialPort.Open();
                _logger.LogInformation("GPS connected successfully");
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to connect to GPS");
                return false;
            }
        }

        public async Task StartCapture(CancellationToken cancellationToken = default)
        {
            if (_serialPort == null || !_serialPort.IsOpen)
            {
                throw new InvalidOperationException("GPS not connected. Call Connect() first.");
            }

            _isRunning = true;
            _logger.LogInformation("Starting GPS data capture...");

            var lastCaptureTime = DateTime.MinValue;
            var currentData = new GpsData
            {
                DeviceId = Environment.MachineName,
                Timestamp = DateTime.UtcNow
            };

            try
            {
                while (_isRunning && !cancellationToken.IsCancellationRequested)
                {
                    try
                    {
                        var line = await Task.Run(() => _serialPort.ReadLine(), cancellationToken);

                        if (string.IsNullOrWhiteSpace(line) || !line.StartsWith("$"))
                            continue;

                        var sentence = NmeaSentenceParser.Parse(line);
                        if (sentence != null)
                        {
                            UpdateGpsData(currentData, sentence);

                            // Emit data at configured interval
                            if ((DateTime.UtcNow - lastCaptureTime).TotalSeconds >= _settings.CaptureIntervalSeconds)
                            {
                                if (currentData.Latitude.HasValue && currentData.Longitude.HasValue)
                                {
                                    currentData.Timestamp = DateTime.UtcNow;
                                    DataReceived?.Invoke(this, CloneGpsData(currentData));
                                    lastCaptureTime = DateTime.UtcNow;
                                }
                            }
                        }
                    }
                    catch (TimeoutException)
                    {
                        continue;
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "Error reading GPS data");
                        await Task.Delay(1000, cancellationToken);
                    }
                }
            }
            finally
            {
                _isRunning = false;
                _logger.LogInformation("GPS data capture stopped");
            }
        }

        private void UpdateGpsData(GpsData data, NmeaSentence sentence)
        {
            switch (sentence)
            {
                case RMCSentence rmc:
                    if (rmc.Latitude.HasValue)
                        data.Latitude = rmc.Latitude.Value;

                    if (rmc.Longitude.HasValue)
                        data.Longitude = rmc.Longitude.Value;

                    if (rmc.SpeedKnots.HasValue)
                    {
                        data.SpeedKmh = rmc.SpeedKnots.Value * 1.852; // knots to km/h
                        data.SpeedMph = rmc.SpeedKnots.Value * 1.15078; // knots to mph
                    }

                    if (rmc.Course.HasValue)
                    {
                        data.Course = rmc.Course.Value;
                        data.CourseDirection = GpsData.GetDirection(rmc.Course.Value);
                    }

                    data.Status = rmc.Status == "A" ? "A" : "V";
                    break;

                case GGASentence gga:
                    if (gga.Latitude.HasValue)
                        data.Latitude = gga.Latitude.Value;

                    if (gga.Longitude.HasValue)
                        data.Longitude = gga.Longitude.Value;

                    if (gga.Altitude.HasValue)
                        data.Altitude = gga.Altitude.Value;

                    if (gga.Satellites.HasValue)
                        data.Satellites = gga.Satellites.Value;

                    if (gga.Quality.HasValue)
                        data.FixQuality = gga.Quality.Value;

                    if (gga.HDOP.HasValue)
                        data.Hdop = gga.HDOP.Value;
                    break;

                case VTGSentence vtg:
                    if (vtg.SpeedKmh.HasValue)
                        data.SpeedKmh = vtg.SpeedKmh.Value;

                    if (vtg.SpeedKnots.HasValue)
                        data.SpeedMph = vtg.SpeedKnots.Value * 1.15078;

                    if (vtg.CourseTrue.HasValue)
                    {
                        data.Course = vtg.CourseTrue.Value;
                        data.CourseDirection = GpsData.GetDirection(vtg.CourseTrue.Value);
                    }
                    break;
            }
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

        public void Stop()
        {
            _isRunning = false;
        }

        public void Dispose()
        {
            _serialPort?.Close();
            _serialPort?.Dispose();
        }
    }
}
