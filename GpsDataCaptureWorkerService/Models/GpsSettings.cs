namespace GpsDataCaptureWorkerService.Models
{
    public class GpsSettings
    {
        public DataMode Mode { get; set; } = DataMode.SaveToFile;
        public int BaudRate { get; set; } = 4800;
        public string? PortName { get; set; }
        public bool AutoDetectPort { get; set; } = true;
        public int CaptureIntervalSeconds { get; set; } = 5;
        public List<string> SaveFormats { get; set; } = new() { "json" };//{ "csv", "json" };
        public string DataDirectory { get; set; } = "gps_data";
        public string ApiEndpoint { get; set; } = string.Empty;
        public string ApiKey { get; set; } = string.Empty;
        public int ApiTimeoutSeconds { get; set; } = 30;
        public int RetryAttempts { get; set; } = 3;
        public int BatchSize { get; set; } = 10;
        public bool EnableLogging { get; set; } = true;
    }
}
