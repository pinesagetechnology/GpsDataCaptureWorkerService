using GpsDataCaptureWorkerService.GPSProcessing;
using GpsDataCaptureWorkerService.Models;

namespace GpsDataCaptureWorkerService.Services
{
    public static class GPSServiceLayerExtension
    {
        public static IServiceCollection AddGPSServiceLayer(this IServiceCollection services, IConfiguration configuration)
        {
            // Configure GpsSettings from appsettings.json
            services.Configure<GpsSettings>(configuration.GetSection("GpsSettings"));

            // Register GPS services
            services.AddSingleton<GpsPortDetector>();
            services.AddSingleton<IGpsReaderService, GpsReaderService>();
            services.AddSingleton<GpsReaderService>();
            
            // Register storage service
            services.AddSingleton<IFileStorageService, FileStorageService>();
            services.AddSingleton<FileStorageService>();
            
            // Register API sender service
            services.AddSingleton<IApiSenderService, ApiSenderService>();
            services.AddSingleton<ApiSenderService>();
            
            // Add HttpClient factory for proper lifecycle management
            services.AddHttpClient();

            return services;
        }
    }
}
