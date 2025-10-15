namespace GpsDataCaptureWorkerService
{
    public enum DataMode
    {
        SaveToFile,
        SendToApi,
        SendToAzureStorage,
        FileAndApi,
        FileAndAzure,
        ApiAndAzure,
        All
    }
}
