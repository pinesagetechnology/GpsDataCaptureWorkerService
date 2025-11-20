namespace GpsDataCaptureWorkerService
{
    public enum DataMode
    {
        SaveToFile,
        SendToApi,
        SendToAzureStorage,
        SaveToPostgres,
        FileAndApi,
        FileAndAzure,
        FileAndPostgres,
        ApiAndAzure,
        ApiAndPostgres,
        AzureAndPostgres,
        FileApiAndPostgres,
        FileAzureAndPostgres,
        ApiAzureAndPostgres,
        All
    }
}
