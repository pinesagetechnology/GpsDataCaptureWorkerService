# Azure Storage Setup Guide

This guide explains how to configure the GPS Data Capture Worker Service to upload data to Azure Blob Storage.

## Prerequisites

- Azure Subscription
- Azure Storage Account

## Step 1: Create Azure Storage Account

1. Sign in to the [Azure Portal](https://portal.azure.com)
2. Create a new Storage Account:
   - Click "Create a resource"
   - Search for "Storage account"
   - Click "Create"
   - Fill in the required details:
     - **Resource Group**: Select or create one
     - **Storage Account Name**: Choose a unique name (e.g., `gpsdatastorage`)
     - **Region**: Select closest to your IoT devices
     - **Performance**: Standard
     - **Redundancy**: LRS (Locally redundant storage) is sufficient for most IoT scenarios
3. Click "Review + create" and then "Create"

## Step 2: Get Connection String

1. Navigate to your storage account in the Azure Portal
2. In the left menu, under "Security + networking", click "Access keys"
3. Click "Show keys"
4. Copy either "Connection string" from key1 or key2

## Step 3: Configure the Service

### Option 1: Using appsettings.json

Edit `appsettings.json` and add your Azure Storage connection string:

```json
{
  "GpsSettings": {
    "Mode": "SendToAzureStorage",
    "AzureStorageConnectionString": "DefaultEndpointsProtocol=https;AccountName=gpsdatastorage;AccountKey=YOUR_KEY_HERE;EndpointSuffix=core.windows.net",
    "AzureStorageContainerName": "gps-data",
    "AzureStoragePrettyJson": false,
    "BatchSize": 10,
    "RetryAttempts": 3
  }
}
```

### Option 2: Using Environment Variables (Recommended for Production)

For security, use environment variables instead of hardcoding the connection string:

**Linux/macOS:**
```bash
export GpsSettings__AzureStorageConnectionString="DefaultEndpointsProtocol=https;AccountName=..."
```

**Windows PowerShell:**
```powershell
$env:GpsSettings__AzureStorageConnectionString = "DefaultEndpointsProtocol=https;AccountName=..."
```

**Windows Service:**
Add to the service environment variables in the systemd unit file or Windows service configuration.

### Option 3: Using User Secrets (Development)

For development, use .NET User Secrets:

```bash
cd GpsDataCaptureWorkerService
dotnet user-secrets set "GpsSettings:AzureStorageConnectionString" "DefaultEndpointsProtocol=https;AccountName=..."
```

## Step 4: Choose Operating Mode

The service supports multiple modes:

### Upload to Azure Storage Only
```json
{
  "GpsSettings": {
    "Mode": "SendToAzureStorage"
  }
}
```

### Save Locally AND Upload to Azure
```json
{
  "GpsSettings": {
    "Mode": "FileAndAzure"
  }
}
```

### Send to API AND Upload to Azure
```json
{
  "GpsSettings": {
    "Mode": "ApiAndAzure"
  }
}
```

### Do Everything (Local + API + Azure)
```json
{
  "GpsSettings": {
    "Mode": "All"
  }
}
```

## Step 5: Start the Service

```bash
cd GpsDataCaptureWorkerService
dotnet run
```

You should see log messages indicating successful uploads to Azure Storage:

```
Successfully uploaded 10 GPS records to Azure Storage: raspberrypi/2024/10/15/gps_data_20241015_143025_abc123.json
```

## Data Structure in Azure Storage

GPS data is organized hierarchically:

```
gps-data/                                    (container)
  └── {device_id}/                           (e.g., "raspberrypi", "gps-device-01")
      └── {year}/                            (e.g., "2024")
          └── {month}/                       (e.g., "10")
              └── {day}/                     (e.g., "15")
                  └── gps_data_{timestamp}_{guid}.json
```

**Example:**
```
gps-data/raspberrypi/2024/10/15/gps_data_20241015_143025_a1b2c3d4e5f6.json
```

## Blob Metadata

Each uploaded blob includes the following metadata:

| Key | Description | Example |
|-----|-------------|---------|
| `RecordCount` | Number of GPS records in the file | `10` |
| `DeviceId` | Device identifier | `raspberrypi` |
| `UploadTimestamp` | When the file was uploaded (ISO 8601) | `2024-10-15T14:30:25.123Z` |
| `FirstRecordTime` | Timestamp of first GPS record | `2024-10-15T14:30:00.000Z` |
| `LastRecordTime` | Timestamp of last GPS record | `2024-10-15T14:30:45.000Z` |

## Configuration Options

| Setting | Type | Description | Default |
|---------|------|-------------|---------|
| `AzureStorageConnectionString` | string | Azure Storage account connection string | - |
| `AzureStorageContainerName` | string | Container name for GPS data | `gps-data` |
| `AzureStoragePrettyJson` | bool | Format JSON with indentation (larger files) | `false` |
| `BatchSize` | int | Number of records per upload | `10` |
| `RetryAttempts` | int | Number of retry attempts on failure | `3` |

## Viewing Data in Azure Portal

1. Navigate to your storage account in the Azure Portal
2. In the left menu, click "Containers" under "Data storage"
3. Click on your container (e.g., `gps-data`)
4. Browse the folder structure to view uploaded files
5. Click on a file to view its contents and metadata

## Querying Data with Azure Storage Explorer

For better data management, use [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/):

1. Download and install Azure Storage Explorer
2. Connect to your Azure account
3. Navigate to your storage account and container
4. Use the search and filter features to find specific GPS data

## Cost Considerations

Azure Blob Storage costs are based on:
- **Storage**: Amount of data stored (per GB per month)
- **Operations**: Number of write/read operations
- **Data transfer**: Egress (data leaving Azure)

**Recommendations:**
- Use `AzureStoragePrettyJson: false` to minimize storage costs
- Adjust `BatchSize` to balance between upload frequency and operation costs
- Consider using archive tier for older GPS data

**Estimated costs for IoT scenarios:**
- GPS data capture every 5 seconds
- 10 records per batch
- ~100 MB of data per month per device
- **Cost**: ~$0.02 - $0.05 per device per month

## Troubleshooting

### Connection String Invalid
**Error:** `Azure Storage request failed (Status: 403)`
**Solution:** Verify your connection string is correct and the storage account key hasn't been regenerated.

### Container Not Found
**Error:** `The specified container does not exist`
**Solution:** The service will automatically create the container. Ensure your connection string has write permissions.

### Network Timeout
**Error:** `Request timeout uploading GPS data to Azure Storage`
**Solution:** 
- Check your internet connection
- Increase `RetryAttempts` in configuration
- Check if Azure services are accessible from your network

### Data Not Appearing
**Issue:** Service runs but no data appears in Azure Storage
**Solution:**
- Check the service logs for errors
- Verify the `Mode` includes Azure Storage (e.g., `SendToAzureStorage`, `FileAndAzure`, etc.)
- Ensure GPS device is connected and providing valid data
- Check that the connection string is configured correctly

## Security Best Practices

1. **Never commit connection strings to source control**
   - Use environment variables or user secrets
   - Add `appsettings.json` with connection strings to `.gitignore`

2. **Use Managed Identity (for Azure-hosted services)**
   - If running on Azure VMs or App Services, use Managed Identity instead of connection strings

3. **Rotate keys regularly**
   - Azure allows two keys - rotate them periodically without downtime

4. **Use SAS tokens for limited access**
   - For temporary access, generate Shared Access Signatures (SAS) instead of using account keys

5. **Enable logging and monitoring**
   - Configure Azure Monitor to track storage access and operations
   - Set up alerts for unusual activity

## Advanced: Using Azure Data Lake Storage Gen2

For advanced analytics, consider upgrading to Azure Data Lake Storage Gen2:

1. Enable "Hierarchical namespace" when creating the storage account
2. Use the same connection string and configuration
3. Benefit from better organization and query performance for large datasets

## Support

For issues specific to:
- **Azure Storage**: [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- **GPS Service**: Create an issue in the project repository

