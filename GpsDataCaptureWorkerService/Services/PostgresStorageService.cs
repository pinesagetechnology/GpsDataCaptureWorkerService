using GpsDataCaptureWorkerService.Models;
using Microsoft.Extensions.Options;
using Npgsql;
using System.Collections.Concurrent;
using System.Text.Json;

namespace GpsDataCaptureWorkerService.Services
{
    public interface IPostgresStorageService
    {
        Task SaveAsync(GpsData data);
        Task FlushAsync();
    }

    public class PostgresStorageService : IPostgresStorageService, IDisposable
    {
        private readonly GpsSettings _settings;
        private readonly ILogger<PostgresStorageService> _logger;
        private readonly ConcurrentQueue<GpsData> _dataQueue;
        private readonly SemaphoreSlim _processLock = new(1, 1);
        private readonly Timer _batchTimer;
        private bool _isProcessing;
        private int _recordCount = 0;
        private int _failedCount = 0;

        // SQL insert statement
        private const string InsertSql = @"
            INSERT INTO gps_data (
                timestamp_utc, latitude, longitude, altitude_meters,
                speed_kmh, speed_mph, course_degrees,
                satellite_count, fix_quality, hdop,
                device_id, raw_data
            ) VALUES (
                @timestamp_utc, @latitude, @longitude, @altitude_meters,
                @speed_kmh, @speed_mph, @course_degrees,
                @satellite_count, @fix_quality, @hdop,
                @device_id, @raw_data
            )";

        public PostgresStorageService(IOptions<GpsSettings> settings, ILogger<PostgresStorageService> logger)
        {
            _settings = settings.Value;
            _logger = logger;
            _dataQueue = new ConcurrentQueue<GpsData>();

            // Start batch processing timer (flush every 10 seconds or when batch size reached)
            _batchTimer = new Timer(async _ => await ProcessBatchAsync(), null, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(10));

            // Test database connection if connection string is provided
            if (!string.IsNullOrEmpty(_settings.PostgresConnectionString))
            {
                TestConnection();
            }
        }

        private void TestConnection()
        {
            try
            {
                using var connection = new NpgsqlConnection(_settings.PostgresConnectionString);
                connection.Open();
                _logger.LogInformation("✓ PostgreSQL connection successful");
                connection.Close();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "✗ Failed to connect to PostgreSQL. Check connection string and database availability.");
                throw;
            }
        }

        public void QueueData(GpsData data)
        {
            _dataQueue.Enqueue(data);

            // Trigger immediate processing if batch size reached
            if (_dataQueue.Count >= _settings.BatchSize)
            {
                _ = Task.Run(async () => await ProcessBatchAsync());
            }
        }

        public async Task SaveAsync(GpsData data)
        {
            // For synchronous saves, queue and process immediately if batch size reached
            QueueData(data);

            // If queue is large enough, process immediately
            if (_dataQueue.Count >= _settings.BatchSize)
            {
                await ProcessBatchAsync();
            }
        }

        public async Task FlushAsync()
        {
            // Process any remaining items in queue
            await ProcessBatchAsync();
        }

        private async Task ProcessBatchAsync()
        {
            if (_isProcessing || _dataQueue.IsEmpty)
                return;

            await _processLock.WaitAsync();
            try
            {
                _isProcessing = true;

                var batch = new List<GpsData>();
                
                // Dequeue items for batch processing
                while (_dataQueue.TryDequeue(out var item) && batch.Count < _settings.BatchSize * 2)
                {
                    batch.Add(item);
                }

                if (batch.Count == 0)
                    return;

                await InsertBatchAsync(batch);
            }
            finally
            {
                _isProcessing = false;
                _processLock.Release();
            }
        }

        private async Task InsertBatchAsync(List<GpsData> batch)
        {
            if (batch.Count == 0)
                return;

            var retries = _settings.RetryAttempts;
            var delay = TimeSpan.FromSeconds(1);

            for (int attempt = 1; attempt <= retries; attempt++)
            {
                try
                {
                    await using var connection = new NpgsqlConnection(_settings.PostgresConnectionString);
                    await connection.OpenAsync();

                    await using var transaction = await connection.BeginTransactionAsync();
                    try
                    {
                        foreach (var data in batch)
                        {
                            await using var command = new NpgsqlCommand(InsertSql, connection, transaction);
                            
                            // Map GpsData to database columns
                            command.Parameters.AddWithValue("@timestamp_utc", data.Timestamp.ToUniversalTime());
                            command.Parameters.AddWithValue("@latitude", (object?)data.Latitude ?? DBNull.Value);
                            command.Parameters.AddWithValue("@longitude", (object?)data.Longitude ?? DBNull.Value);
                            command.Parameters.AddWithValue("@altitude_meters", (object?)data.Altitude ?? DBNull.Value);
                            command.Parameters.AddWithValue("@speed_kmh", (object?)data.SpeedKmh ?? DBNull.Value);
                            command.Parameters.AddWithValue("@speed_mph", (object?)data.SpeedMph ?? DBNull.Value);
                            command.Parameters.AddWithValue("@course_degrees", (object?)data.Course ?? DBNull.Value);
                            command.Parameters.AddWithValue("@satellite_count", (object?)data.Satellites ?? DBNull.Value);
                            command.Parameters.AddWithValue("@fix_quality", GetFixQualityString(data.FixQuality));
                            command.Parameters.AddWithValue("@hdop", (object?)data.Hdop ?? DBNull.Value);
                            command.Parameters.AddWithValue("@device_id", data.DeviceId ?? Environment.MachineName);
                            command.Parameters.AddWithValue("@raw_data", _settings.PostgresStoreRawData ? SerializeRawData(data) : (object?)DBNull.Value);

                            await command.ExecuteNonQueryAsync();
                        }

                        await transaction.CommitAsync();
                        
                        Interlocked.Add(ref _recordCount, batch.Count);
                        _logger.LogDebug("✓ Inserted {Count} GPS records into PostgreSQL", batch.Count);
                        
                        return; // Success, exit retry loop
                    }
                    catch
                    {
                        await transaction.RollbackAsync();
                        throw;
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Attempt {Attempt}/{Retries} failed to insert GPS data batch", attempt, retries);
                    
                    if (attempt < retries)
                    {
                        // Exponential backoff
                        await Task.Delay(delay);
                        delay = TimeSpan.FromMilliseconds(delay.TotalMilliseconds * 2);
                    }
                    else
                    {
                        // All retries failed
                        Interlocked.Add(ref _failedCount, batch.Count);
                        _logger.LogError(ex, "✗ Failed to insert GPS data batch after {Retries} attempts. {Count} records lost.", retries, batch.Count);
                        
                        // Optionally re-queue for later retry (could implement a dead-letter queue)
                        foreach (var item in batch)
                        {
                            _dataQueue.Enqueue(item); // Re-queue for next attempt
                        }
                    }
                }
            }
        }

        private string GetFixQualityString(int? fixQuality)
        {
            if (!fixQuality.HasValue)
                return "NO_FIX";

            return fixQuality.Value switch
            {
                0 => "NO_FIX",
                1 => "2D",
                2 => "3D",
                3 => "DGPS",
                4 => "RTK",
                _ => $"UNKNOWN_{fixQuality.Value}"
            };
        }

        private string SerializeRawData(GpsData data)
        {
            try
            {
                var options = new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                };
                return JsonSerializer.Serialize(data, options);
            }
            catch
            {
                return string.Empty;
            }
        }

        public void Dispose()
        {
            _batchTimer?.Dispose();
            _processLock?.Dispose();
            
            _logger.LogInformation("=== PostgreSQL Storage Summary ===");
            _logger.LogInformation("Total records saved: {Count}", _recordCount);
            _logger.LogInformation("Failed records: {Count}", _failedCount);
        }
    }
}

