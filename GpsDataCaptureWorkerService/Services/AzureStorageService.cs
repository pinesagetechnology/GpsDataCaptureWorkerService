using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using GpsDataCaptureWorkerService.Models;
using Microsoft.Extensions.Options;
using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;

namespace GpsDataCaptureWorkerService.Services
{
    public interface IAzureStorageService
    {
        void QueueData(GpsData data);
        Task FlushAsync();
    }

    public class AzureStorageService : IAzureStorageService, IDisposable
    {
        private readonly GpsSettings _settings;
        private readonly ILogger<AzureStorageService> _logger;
        private readonly BlobServiceClient? _blobServiceClient;
        private readonly BlobContainerClient? _containerClient;
        private readonly ConcurrentQueue<GpsData> _dataQueue;
        private readonly Timer _batchTimer;
        private bool _isProcessing;
        private bool _isInitialized;

        public AzureStorageService(IOptions<GpsSettings> settings, ILogger<AzureStorageService> logger)
        {
            _settings = settings.Value;
            _logger = logger;
            _dataQueue = new ConcurrentQueue<GpsData>();

            // Initialize Azure Storage client if connection string is provided
            if (!string.IsNullOrEmpty(_settings.AzureStorageConnectionString))
            {
                try
                {
                    _blobServiceClient = new BlobServiceClient(_settings.AzureStorageConnectionString);
                    _containerClient = _blobServiceClient.GetBlobContainerClient(_settings.AzureStorageContainerName);
                    
                    // Ensure container exists
                    _ = InitializeContainerAsync();
                    
                    _isInitialized = true;
                    _logger.LogInformation("Azure Storage Service initialized. Container: {Container}, Batch size: {BatchSize}",
                        _settings.AzureStorageContainerName, _settings.BatchSize);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to initialize Azure Storage client. Connection string may be invalid.");
                    _isInitialized = false;
                }
            }
            else
            {
                _logger.LogWarning("Azure Storage connection string not configured. Service will not upload data.");
                _isInitialized = false;
            }

            // Batch processing timer
            _batchTimer = new Timer(ProcessBatchCallback, null,
                TimeSpan.FromSeconds(10),
                TimeSpan.FromSeconds(10));
        }

        private async Task InitializeContainerAsync()
        {
            try
            {
                if (_containerClient != null)
                {
                    await _containerClient.CreateIfNotExistsAsync(PublicAccessType.None);
                    _logger.LogInformation("Azure Storage container '{Container}' is ready", _settings.AzureStorageContainerName);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to create or access Azure Storage container: {Container}",
                    _settings.AzureStorageContainerName);
                _isInitialized = false;
            }
        }

        public void QueueData(GpsData data)
        {
            if (!_isInitialized)
            {
                _logger.LogWarning("Azure Storage Service not initialized. Data will not be queued.");
                return;
            }

            _dataQueue.Enqueue(data);
            _logger.LogDebug("GPS data queued for Azure Storage upload. Queue size: {Size}", _dataQueue.Count);

            // Process immediately if batch size is reached
            if (_dataQueue.Count >= _settings.BatchSize)
            {
                _ = ProcessBatchAsync();
            }
        }

        private void ProcessBatchCallback(object? state)
        {
            if (!_isProcessing && !_dataQueue.IsEmpty && _isInitialized)
            {
                _ = ProcessBatchAsync();
            }
        }

        private async Task ProcessBatchAsync()
        {
            if (_isProcessing || !_isInitialized || _containerClient == null) return;

            _isProcessing = true;

            try
            {
                var batch = new List<GpsData>();

                while (batch.Count < _settings.BatchSize && _dataQueue.TryDequeue(out var data))
                {
                    batch.Add(data);
                }

                if (batch.Count == 0) return;

                _logger.LogInformation("Uploading batch of {Count} GPS records to Azure Storage", batch.Count);

                var success = await UploadBatchWithRetryAsync(batch);

                if (!success)
                {
                    _logger.LogWarning("Failed to upload batch to Azure Storage after {Attempts} attempts. Data may be lost.",
                        _settings.RetryAttempts);
                }
            }
            finally
            {
                _isProcessing = false;
            }
        }

        private async Task<bool> UploadBatchWithRetryAsync(List<GpsData> batch)
        {
            if (_containerClient == null) return false;

            for (int attempt = 1; attempt <= _settings.RetryAttempts; attempt++)
            {
                try
                {
                    // Create a filename with timestamp
                    var timestamp = DateTime.UtcNow;
                    var fileName = $"gps_data_{timestamp:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.json";
                    
                    // Use device ID in path if available
                    var deviceId = batch.FirstOrDefault()?.DeviceId ?? "unknown";
                    var blobName = $"{deviceId}/{timestamp:yyyy}/{timestamp:MM}/{timestamp:dd}/{fileName}";

                    // Serialize data to JSON
                    var jsonOptions = new JsonSerializerOptions
                    {
                        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                        WriteIndented = _settings.AzureStoragePrettyJson
                    };

                    var jsonContent = batch.Count == 1 
                        ? JsonSerializer.Serialize(batch[0], jsonOptions)
                        : JsonSerializer.Serialize(batch, jsonOptions);

                    var blobClient = _containerClient.GetBlobClient(blobName);

                    // Upload with metadata
                    var content = Encoding.UTF8.GetBytes(jsonContent);
                    using var stream = new MemoryStream(content);

                    var metadata = new Dictionary<string, string>
                    {
                        { "RecordCount", batch.Count.ToString() },
                        { "DeviceId", deviceId },
                        { "UploadTimestamp", timestamp.ToString("O") },
                        { "FirstRecordTime", batch.First().Timestamp.ToString("O") },
                        { "LastRecordTime", batch.Last().Timestamp.ToString("O") }
                    };

                    var uploadOptions = new BlobUploadOptions
                    {
                        Metadata = metadata,
                        HttpHeaders = new BlobHttpHeaders
                        {
                            ContentType = "application/json"
                        }
                    };

                    await blobClient.UploadAsync(stream, uploadOptions);

                    _logger.LogInformation(
                        "Successfully uploaded {Count} GPS records to Azure Storage: {BlobName}",
                        batch.Count, blobName);
                    
                    return true;
                }
                catch (RequestFailedException ex)
                {
                    _logger.LogError(ex, "Azure Storage request failed (Status: {Status}). Attempt {Attempt}/{Total}",
                        ex.Status, attempt, _settings.RetryAttempts);

                    if (attempt < _settings.RetryAttempts)
                    {
                        await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt))); // Exponential backoff
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error uploading GPS data to Azure Storage. Attempt {Attempt}/{Total}",
                        attempt, _settings.RetryAttempts);

                    if (attempt < _settings.RetryAttempts)
                    {
                        await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)));
                    }
                }
            }

            return false;
        }

        public async Task FlushAsync()
        {
            _logger.LogInformation("Flushing remaining GPS data to Azure Storage...");

            while (!_dataQueue.IsEmpty)
            {
                await ProcessBatchAsync();
                await Task.Delay(100);
            }
        }

        public void Dispose()
        {
            _batchTimer?.Change(Timeout.Infinite, Timeout.Infinite);
            _batchTimer?.Dispose();

            _logger.LogDebug("Azure Storage Service disposed. Queue had {Count} items remaining", _dataQueue.Count);
        }
    }
}

