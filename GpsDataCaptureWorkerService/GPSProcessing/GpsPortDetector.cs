using System.IO.Ports;
using System.Runtime.InteropServices;

namespace GpsDataCaptureWorkerService.GPSProcessing;

public class GpsPortDetector
{
    private readonly ILogger<GpsPortDetector> _logger;

    public GpsPortDetector(ILogger<GpsPortDetector> logger)
    {
        _logger = logger;
    }

    public string? DetectGpsPort()
    {
        _logger.LogInformation("Detecting GPS port...");

        var candidates = GetCandidatePorts();

        if (candidates.Count == 0)
        {
            _logger.LogWarning("No candidate GPS ports found");
            return null;
        }

        _logger.LogInformation("Found {Count} candidate port(s): {Ports}",
            candidates.Count, string.Join(", ", candidates));

        foreach (var port in candidates)
        {
            if (TestPort(port))
            {
                _logger.LogInformation("GPS detected on port: {Port}", port);
                return port;
            }
        }

        return null;
    }

    private List<string> GetCandidatePorts()
    {
        var candidates = new List<string>();

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            // Check for stable device paths first
            var byIdPath = "/dev/serial/by-id";
            if (Directory.Exists(byIdPath))
            {
                var devices = Directory.GetFiles(byIdPath);
                candidates.AddRange(devices);
            }

            // Check common Linux USB serial devices
            candidates.AddRange(Directory.GetFiles("/dev", "ttyACM*"));
            candidates.AddRange(Directory.GetFiles("/dev", "ttyUSB*"));
        }
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            // Windows COM ports
            candidates.AddRange(SerialPort.GetPortNames());
        }
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            // macOS serial devices
            candidates.AddRange(Directory.GetFiles("/dev", "tty.usbserial*"));
            candidates.AddRange(Directory.GetFiles("/dev", "tty.SLAB_USBtoUART*"));
        }

        return candidates.Distinct().ToList();
    }

    private bool TestPort(string portName)
    {
        try
        {
            _logger.LogDebug("Testing port: {Port}", portName);

            using var port = new SerialPort(portName, 4800, Parity.None, 8, StopBits.One)
            {
                ReadTimeout = 3000,
                WriteTimeout = 3000
            };

            port.Open();

            var startTime = DateTime.UtcNow;
            var timeout = TimeSpan.FromSeconds(5);

            while (DateTime.UtcNow - startTime < timeout)
            {
                try
                {
                    var line = port.ReadLine();
                    if (line.StartsWith("$GP") || line.StartsWith("$GN"))
                    {
                        _logger.LogDebug("Valid NMEA data received from {Port}", portName);
                        return true;
                    }
                }
                catch (TimeoutException)
                {
                    continue;
                }
            }

            return false;
        }
        catch (Exception ex)
        {
            _logger.LogDebug("Failed to test port {Port}: {Error}", portName, ex.Message);
            return false;
        }
    }
}