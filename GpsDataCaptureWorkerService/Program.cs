using GpsDataCaptureWorkerService;
using GpsDataCaptureWorkerService.Services;

var builder = Host.CreateDefaultBuilder(args);

if (OperatingSystem.IsWindows())
{
    builder.UseWindowsService();
}
else if (OperatingSystem.IsLinux())
{
    builder.UseSystemd();
}

builder.ConfigureLogging(logging =>
{
    logging.ClearProviders();
    logging.AddConsole();
});


builder.ConfigureServices((hostContext, services) =>
{
    GPSServiceLayerExtension.AddGPSServiceLayer(services, hostContext.Configuration);

    services.AddHostedService<Worker>();
});

var host = builder.Build();
host.Run();
