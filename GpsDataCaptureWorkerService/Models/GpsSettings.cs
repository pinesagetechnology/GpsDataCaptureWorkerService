namespace GpsDataCaptureWorkerService.Models
{
    public class GpsSettings
    {
        // General GPS Settings
        public DataMode Mode { get; set; } = DataMode.SaveToFile;
        public int BaudRate { get; set; } = 4800;
        public string? PortName { get; set; }
        public bool AutoDetectPort { get; set; } = true;
        public int CaptureIntervalSeconds { get; set; } = 5;
        public bool EnableLogging { get; set; } = true;

        // File Storage Settings
        public List<string> SaveFormats { get; set; } = new() { "json" };//{ "csv", "json" };
        public string DataDirectory { get; set; } = "gps_data";

        // API Settings
        public string ApiEndpoint { get; set; } = string.Empty;
        public string ApiKey { get; set; } = string.Empty;
        public int ApiTimeoutSeconds { get; set; } = 30;

        // Azure Storage Settings
        public string AzureStorageConnectionString { get; set; } = string.Empty;
        public string AzureStorageContainerName { get; set; } = "gps-data";
        public bool AzureStoragePrettyJson { get; set; } = false;

        // Common Settings (used by API and Azure Storage)
        public int RetryAttempts { get; set; } = 3;
        public int BatchSize { get; set; } = 10;

        // Movement Detection Settings
        public double MinimumMovementDistanceMeters { get; set; } = 10.0; // Only save/send if vehicle moved at least this distance
    }
}
