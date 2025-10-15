using CsvHelper;
using GpsDataCaptureWorkerService.Models;
using Microsoft.Extensions.Options;
using System.Globalization;
using System.Text.Json;

namespace GpsDataCaptureWorkerService.Services
{
    public interface IFileStorageService
    {
        Task SaveAsync(GpsData data);
        void PrintSummary();
    }

    public class FileStorageService : IFileStorageService
    {
        private readonly GpsSettings _settings;
        private readonly ILogger<FileStorageService> _logger;
        private readonly string _dataDirectory;
        private string? _csvFilePath;
        private string? _jsonFilePath;
        private string? _ndjsonFilePath;
        private readonly SemaphoreSlim _csvLock = new(1, 1);
        private readonly SemaphoreSlim _jsonLock = new(1, 1);
        private readonly SemaphoreSlim _ndjsonLock = new(1, 1);
        private int _recordCount = 0;

        public FileStorageService(IOptions<GpsSettings> settings, ILogger<FileStorageService> logger)
        {
            _settings = settings.Value;
            _logger = logger;
            _dataDirectory = _settings.DataDirectory;

            EnsureDataDirectory();
        }

        private void EnsureDataDirectory()
        {
            if (!Directory.Exists(_dataDirectory))
            {
                Directory.CreateDirectory(_dataDirectory);
                _logger.LogInformation("Created data directory: {Directory}", _dataDirectory);
            }
        }

        public async Task SaveAsync(GpsData data)
        {
            var tasks = new List<Task>();

            if (_settings.SaveFormats.Contains("csv"))
            {
                tasks.Add(SaveToCsvAsync(data));
            }

            if (_settings.SaveFormats.Contains("json"))
            {
                tasks.Add(SaveToJsonAsync(data));
            }

            if (_settings.SaveFormats.Contains("ndjson"))
            {
                tasks.Add(SaveToNdjsonAsync(data));
            }

            await Task.WhenAll(tasks);
            Interlocked.Increment(ref _recordCount);
        }

        private async Task SaveToCsvAsync(GpsData data)
        {
            await _csvLock.WaitAsync();
            try
            {
                _csvFilePath ??= GetFilePath("csv");

                var fileExists = File.Exists(_csvFilePath);

                using var stream = new FileStream(_csvFilePath, FileMode.Append, FileAccess.Write, FileShare.Read);
                using var writer = new StreamWriter(stream);
                using var csv = new CsvWriter(writer, CultureInfo.InvariantCulture);

                if (!fileExists)
                {
                    csv.WriteHeader<GpsData>();
                    await csv.NextRecordAsync();
                }

                csv.WriteRecord(data);
                await csv.NextRecordAsync();

                _logger.LogDebug("Saved GPS data to CSV: {File}", _csvFilePath);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to save GPS data to CSV");
            }
            finally
            {
                _csvLock.Release();
            }
        }

        private async Task SaveToJsonAsync(GpsData data)
        {
            await _jsonLock.WaitAsync();
            try
            {
                _jsonFilePath ??= GetFilePath("json");

                var dataList = new List<GpsData>();

                if (File.Exists(_jsonFilePath))
                {
                    var existingJson = await File.ReadAllTextAsync(_jsonFilePath);
                    if (!string.IsNullOrWhiteSpace(existingJson))
                    {
                        dataList = JsonSerializer.Deserialize<List<GpsData>>(existingJson) ?? new List<GpsData>();
                    }
                }

                dataList.Add(data);

                var options = new JsonSerializerOptions
                {
                    WriteIndented = true,
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                };

                var json = JsonSerializer.Serialize(dataList, options);
                await File.WriteAllTextAsync(_jsonFilePath, json);

                _logger.LogDebug("Saved GPS data to JSON: {File}", _jsonFilePath);
                _logger.LogWarning("JSON format reads entire file on each save. Consider using 'ndjson' format for better performance.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to save GPS data to JSON");
            }
            finally
            {
                _jsonLock.Release();
            }
        }

        private async Task SaveToNdjsonAsync(GpsData data)
        {
            await _ndjsonLock.WaitAsync();
            try
            {
                _ndjsonFilePath ??= GetFilePath("ndjson");

                var options = new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                };

                var json = JsonSerializer.Serialize(data, options);

                // Append single line of JSON (newline-delimited JSON format)
                using var stream = new FileStream(_ndjsonFilePath, FileMode.Append, FileAccess.Write, FileShare.Read);
                using var writer = new StreamWriter(stream);
                await writer.WriteLineAsync(json);

                _logger.LogDebug("Saved GPS data to NDJSON: {File}", _ndjsonFilePath);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to save GPS data to NDJSON");
            }
            finally
            {
                _ndjsonLock.Release();
            }
        }

        private string GetFilePath(string extension)
        {
            var timestamp = DateTime.Now.ToString("yyyyMMdd");
            var filename = $"gps_data_{timestamp}.{extension}";
            return Path.Combine(_dataDirectory, filename);
        }

        public void PrintSummary()
        {
            _logger.LogInformation("=== File Storage Summary ===");
            _logger.LogInformation("Data files saved in: {Directory}", Path.GetFullPath(_dataDirectory));
            _logger.LogInformation("Total records saved: {Count}", _recordCount);

            if (_csvFilePath != null && File.Exists(_csvFilePath))
            {
                var fileInfo = new FileInfo(_csvFilePath);
                _logger.LogInformation("CSV file: {File} ({Size} bytes)", 
                    Path.GetFileName(_csvFilePath), fileInfo.Length);
            }

            if (_jsonFilePath != null && File.Exists(_jsonFilePath))
            {
                var fileInfo = new FileInfo(_jsonFilePath);
                _logger.LogInformation("JSON file: {File} ({Size} bytes)", 
                    Path.GetFileName(_jsonFilePath), fileInfo.Length);
            }

            if (_ndjsonFilePath != null && File.Exists(_ndjsonFilePath))
            {
                var fileInfo = new FileInfo(_ndjsonFilePath);
                _logger.LogInformation("NDJSON file: {File} ({Size} bytes)", 
                    Path.GetFileName(_ndjsonFilePath), fileInfo.Length);
            }
        }

        public void Dispose()
        {
            _csvLock?.Dispose();
            _jsonLock?.Dispose();
            _ndjsonLock?.Dispose();
        }
    }
}
