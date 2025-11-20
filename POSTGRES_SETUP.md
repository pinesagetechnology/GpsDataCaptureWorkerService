# PostgreSQL Integration Setup

This document describes how to configure the GPS Data Capture Worker Service to save GPS data to PostgreSQL.

## Overview

The service now supports saving GPS data directly to PostgreSQL database. This is ideal for:
- ✅ Real-time data storage and querying
- ✅ Integration with existing PostgreSQL infrastructure
- ✅ Complex queries and analytics
- ✅ Multi-device tracking with database views
- ✅ Data persistence without file management

## Database Schema

The service uses the following table structure (from `add_gps_data_table.sql`):

```sql
CREATE TABLE gps_data (
    id SERIAL PRIMARY KEY,
    timestamp_utc TIMESTAMP WITH TIME ZONE NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    altitude_meters DECIMAL(10, 2),
    speed_kmh DECIMAL(6, 2),
    speed_mph DECIMAL(6, 2),
    course_degrees DECIMAL(5, 2),
    satellite_count INTEGER,
    fix_quality VARCHAR(20),
    hdop DECIMAL(4, 2),
    device_id VARCHAR(100) NOT NULL,
    raw_data TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

## Setup Instructions

### 1. Create Database Schema

Run the provided SQL script to create the table and views:

```bash
# On your Raspberry Pi
psql -U iot_gateway_user -d iot_gateway -f add_gps_data_table.sql
```

Or connect and run the SQL:

```bash
psql -h localhost -p 5432 -U iot_gateway_user -d iot_gateway
```

Then paste the contents of `add_gps_data_table.sql`.

### 2. Configure the Service

Edit `appsettings.json` (or `appsettings.Development.json` for development):

```json
{
  "GpsSettings": {
    "Mode": "SaveToPostgres",
    "PostgresConnectionString": "Host=localhost;Port=5432;Database=iot_gateway;Username=iot_gateway_user;Password=7812;Pooling=true;Minimum Pool Size=1;Maximum Pool Size=10;",
    "PostgresStoreRawData": false,
    "BaudRate": 4800,
    "AutoDetectPort": true,
    "CaptureIntervalSeconds": 5,
    "MinimumMovementDistanceMeters": 10.0,
    "RetryAttempts": 3,
    "BatchSize": 10
  }
}
```

### 3. Available Operating Modes

The service supports multiple modes with PostgreSQL:

| Mode | Description |
|------|-------------|
| `SaveToPostgres` | Save only to PostgreSQL |
| `FileAndPostgres` | Save to both files and PostgreSQL |
| `ApiAndPostgres` | Send to API and save to PostgreSQL |
| `AzureAndPostgres` | Upload to Azure and save to PostgreSQL |
| `FileApiAndPostgres` | Save to files, send to API, and save to PostgreSQL |
| `FileAzureAndPostgres` | Save to files, upload to Azure, and save to PostgreSQL |
| `ApiAzureAndPostgres` | Send to API, upload to Azure, and save to PostgreSQL |
| `All` | Use all storage methods (files, API, Azure, PostgreSQL) |

### 4. Configuration Options

#### PostgreSQL Settings

- **`PostgresConnectionString`** (required): PostgreSQL connection string
  - Format: `Host=localhost;Port=5432;Database=iot_gateway;Username=user;Password=pass;`
  - See [Npgsql Connection Strings](https://www.npgsql.org/doc/connection-string-parameters.html) for full options

- **`PostgresStoreRawData`** (optional, default: `false`): 
  - If `true`, stores raw GPS data as JSON in the `raw_data` column
  - If `false`, `raw_data` column will be NULL
  - Useful for debugging or preserving original data

#### Common Settings

- **`BatchSize`** (default: 10): Number of GPS records to batch before inserting into database
- **`RetryAttempts`** (default: 3): Number of retry attempts on database insertion failures
- **`MinimumMovementDistanceMeters`** (default: 10.0): Only save GPS data if vehicle moved at least this distance

## Features

### Automatic Batch Processing

GPS data is automatically batched and inserted efficiently:
- Batches are processed when `BatchSize` is reached OR every 10 seconds
- Uses database transactions for atomic inserts
- Retry logic with exponential backoff on failures

### Fix Quality Mapping

The service automatically maps GPS fix quality integers to database strings:

| Integer | Database Value | Description |
|---------|---------------|-------------|
| 0 | `NO_FIX` | No GPS fix |
| 1 | `2D` | 2D GPS fix |
| 2 | `3D` | 3D GPS fix |
| 3 | `DGPS` | Differential GPS |
| 4 | `RTK` | Real-Time Kinematic |

### Connection Pooling

The service uses Npgsql connection pooling (configured in connection string):
- **`Pooling=true`**: Enables connection pooling
- **`Minimum Pool Size=1`**: Keeps at least 1 connection ready
- **`Maximum Pool Size=10`**: Limits to 10 concurrent connections

This ensures efficient database access without connection overhead.

## Example Queries

### Latest Position for Each Device

```sql
SELECT * FROM v_gps_latest_positions;
```

### Device Summary Statistics

```sql
SELECT * FROM v_gps_device_summary;
```

### Recent GPS Data (Last 24 Hours)

```sql
SELECT * FROM v_gps_recent_24h 
WHERE device_id = 'raspberry-pi-001'
ORDER BY timestamp_utc DESC;
```

### GPS Track for a Device

```sql
SELECT * FROM get_gps_track(
    'raspberry-pi-001',
    '2024-10-15 00:00:00'::timestamp with time zone,
    '2024-10-15 23:59:59'::timestamp with time zone
);
```

### Distance Traveled

```sql
SELECT calculate_distance_traveled(
    'raspberry-pi-001',
    '2024-10-15 00:00:00'::timestamp with time zone,
    '2024-10-15 23:59:59'::timestamp with time zone
);
```

### Quality Report

```sql
SELECT * FROM v_gps_quality_report
WHERE device_id = 'raspberry-pi-001'
ORDER BY date DESC;
```

## Troubleshooting

### Connection Failed

**Error:** `✗ Failed to connect to PostgreSQL`

**Solutions:**
1. Verify PostgreSQL is running: `sudo systemctl status postgresql`
2. Check connection string in `appsettings.json`
3. Verify database exists: `psql -U iot_gateway_user -d iot_gateway -c "\dt"`
4. Check table exists: `psql -U iot_gateway_user -d iot_gateway -c "\d gps_data"`
5. Test connection manually: `psql -h localhost -p 5432 -U iot_gateway_user -d iot_gateway`

### Permission Denied

**Error:** `permission denied for table gps_data`

**Solution:**
```sql
GRANT INSERT, SELECT ON gps_data TO iot_gateway_user;
GRANT USAGE, SELECT ON SEQUENCE gps_data_id_seq TO iot_gateway_user;
```

### Table Does Not Exist

**Error:** `relation "gps_data" does not exist`

**Solution:**
Run the `add_gps_data_table.sql` script to create the table and views.

### High Latency

**Issue:** Slow database inserts

**Solutions:**
1. Increase `BatchSize` (e.g., 20-50) to reduce insert frequency
2. Ensure PostgreSQL indexes are created (included in SQL script)
3. Check PostgreSQL performance: `EXPLAIN ANALYZE INSERT INTO gps_data...`
4. Consider using `UNLOGGED` table for high-volume temporary data (not recommended for production)

## Performance Considerations

### Recommended Settings for Raspberry Pi

```json
{
  "BatchSize": 20,
  "RetryAttempts": 3,
  "MinimumMovementDistanceMeters": 10.0
}
```

### For High-Frequency GPS (sub-second intervals)

```json
{
  "BatchSize": 50,
  "RetryAttempts": 5,
  "MinimumMovementDistanceMeters": 5.0
}
```

### Database Maintenance

The SQL script includes a cleanup function. Schedule it to run periodically:

```sql
-- Delete GPS data older than 90 days
SELECT cleanup_old_gps_data(90);

-- Or schedule in cron/pg_cron:
-- 0 2 * * * psql -U iot_gateway_user -d iot_gateway -c "SELECT cleanup_old_gps_data(90);"
```

## Migration from File Storage

If you're currently using file storage and want to migrate:

1. **Keep both modes temporarily:**
   ```json
   "Mode": "FileAndPostgres"
   ```

2. **Verify PostgreSQL data is correct**

3. **Switch to PostgreSQL only:**
   ```json
   "Mode": "SaveToPostgres"
   ```

4. **Optionally import historical data** from files using a script or PostgreSQL's COPY command

## Security Notes

⚠️ **Important:** The connection string contains credentials. 

- Never commit `appsettings.json` with real passwords to version control
- Use environment variables for production:
  ```json
  "PostgresConnectionString": "Host=localhost;Port=5432;Database=iot_gateway;Username=iot_gateway_user;Password=${POSTGRES_PASSWORD};"
  ```
- Restrict database user permissions (only INSERT, SELECT needed)
- Use SSL for remote connections: `SSL Mode=Require;`

## Support

For issues:
1. Check service logs: `sudo journalctl -u gpsdatacapture -f`
2. Verify PostgreSQL logs: `sudo tail -f /var/log/postgresql/postgresql-*.log`
3. Test connection: `psql -h localhost -p 5432 -U iot_gateway_user -d iot_gateway`

