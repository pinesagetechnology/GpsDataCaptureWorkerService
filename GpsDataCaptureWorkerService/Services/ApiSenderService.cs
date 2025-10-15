using GpsDataCaptureWorkerService.Models;
using Microsoft.Extensions.Options;
using System.Collections.Concurrent;
using System.Net.Http.Json;
using System.Text.Json;

namespace GpsDataCaptureWorkerService.Services
{
    public interface IApiSenderService
    {
        void QueueData(GpsData data);
        Task FlushAsync();
    }

    public class ApiSenderService : IApiSenderService, IDisposable
    {
        private readonly GpsSettings _settings;
        private readonly ILogger<ApiSenderService> _logger;
        private readonly HttpClient _httpClient;
        private readonly ConcurrentQueue<GpsData> _dataQueue;
        private readonly Timer _batchTimer;
        private bool _isProcessing;

        public ApiSenderService(IOptions<GpsSettings> settings, ILogger<ApiSenderService> logger, IHttpClientFactory httpClientFactory)
        {
            _settings = settings.Value;
            _logger = logger;
            _dataQueue = new ConcurrentQueue<GpsData>();

            _httpClient = httpClientFactory.CreateClient();
            
            // Validate and set base address
            if (!string.IsNullOrEmpty(_settings.ApiEndpoint))
            {
                try
                {
                    _httpClient.BaseAddress = new Uri(_settings.ApiEndpoint);
                }
                catch (UriFormatException ex)
                {
                    _logger.LogError(ex, "Invalid API endpoint URL: {Endpoint}", _settings.ApiEndpoint);
                    throw;
                }
            }
            
            _httpClient.Timeout = TimeSpan.FromSeconds(_settings.ApiTimeoutSeconds);

            if (!string.IsNullOrEmpty(_settings.ApiKey))
            {
                _httpClient.DefaultRequestHeaders.Add("X-API-Key", _settings.ApiKey);
                _httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_settings.ApiKey}");
            }

            _httpClient.DefaultRequestHeaders.Add("User-Agent", "GpsDataCapture/1.0");

            // Batch processing timer
            _batchTimer = new Timer(ProcessBatchCallback, null,
                TimeSpan.FromSeconds(5),
                TimeSpan.FromSeconds(5));
            
            _logger.LogInformation("API Sender Service initialized. Batch size: {BatchSize}, Retry attempts: {Retries}", 
                _settings.BatchSize, _settings.RetryAttempts);
        }

        public void QueueData(GpsData data)
        {
            _dataQueue.Enqueue(data);
            _logger.LogDebug("GPS data queued for API transmission. Queue size: {Size}", _dataQueue.Count);

            // Process immediately if batch size is reached
            if (_dataQueue.Count >= _settings.BatchSize)
            {
                _ = ProcessBatchAsync();
            }
        }

        private void ProcessBatchCallback(object? state)
        {
            if (!_isProcessing && !_dataQueue.IsEmpty)
            {
                _ = ProcessBatchAsync();
            }
        }

        private async Task ProcessBatchAsync()
        {
            if (_isProcessing) return;

            _isProcessing = true;

            try
            {
                var batch = new List<GpsData>();

                while (batch.Count < _settings.BatchSize && _dataQueue.TryDequeue(out var data))
                {
                    batch.Add(data);
                }

                if (batch.Count == 0) return;

                _logger.LogInformation("Sending batch of {Count} GPS records to API", batch.Count);

                var success = await SendBatchWithRetryAsync(batch);

                if (!success)
                {
                    _logger.LogWarning("Failed to send batch after {Attempts} attempts. Data may be lost.",
                        _settings.RetryAttempts);
                }
            }
            finally
            {
                _isProcessing = false;
            }
        }

        private async Task<bool> SendBatchWithRetryAsync(List<GpsData> batch)
        {
            for (int attempt = 1; attempt <= _settings.RetryAttempts; attempt++)
            {
                try
                {
                    var payload = batch.Count == 1 ? (object)batch[0] : batch;

                    var response = await _httpClient.PostAsJsonAsync("", payload, new JsonSerializerOptions
                    {
                        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                    });

                    if (response.IsSuccessStatusCode)
                    {
                        _logger.LogInformation("Successfully sent {Count} GPS records to API", batch.Count);
                        return true;
                    }

                    _logger.LogWarning("API returned status code: {StatusCode}. Attempt {Attempt}/{Total}",
                        response.StatusCode, attempt, _settings.RetryAttempts);

                    if (attempt < _settings.RetryAttempts)
                    {
                        await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt))); // Exponential backoff
                    }
                }
                catch (HttpRequestException ex)
                {
                    _logger.LogError(ex, "HTTP error sending GPS data. Attempt {Attempt}/{Total}",
                        attempt, _settings.RetryAttempts);

                    if (attempt < _settings.RetryAttempts)
                    {
                        await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)));
                    }
                }
                catch (TaskCanceledException ex)
                {
                    _logger.LogError(ex, "Request timeout sending GPS data. Attempt {Attempt}/{Total}",
                        attempt, _settings.RetryAttempts);

                    if (attempt < _settings.RetryAttempts)
                    {
                        await Task.Delay(TimeSpan.FromSeconds(2));
                    }
                }
            }

            return false;
        }

        public async Task FlushAsync()
        {
            _logger.LogInformation("Flushing remaining GPS data to API...");

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
            _httpClient?.Dispose();
            
            _logger.LogDebug("API Sender Service disposed. Queue had {Count} items remaining", _dataQueue.Count);
        }
    }
}