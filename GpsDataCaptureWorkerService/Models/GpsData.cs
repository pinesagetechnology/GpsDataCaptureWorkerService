using System.Text.Json.Serialization;

namespace GpsDataCaptureWorkerService.Models
{
    public class GpsData
    {
        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonPropertyName("latitude")]
        public double? Latitude { get; set; }

        [JsonPropertyName("longitude")]
        public double? Longitude { get; set; }

        [JsonPropertyName("altitude")]
        public double? Altitude { get; set; }

        [JsonPropertyName("speed_kmh")]
        public double? SpeedKmh { get; set; }

        [JsonPropertyName("speed_mph")]
        public double? SpeedMph { get; set; }

        [JsonPropertyName("course")]
        public double? Course { get; set; }

        [JsonPropertyName("course_direction")]
        public string? CourseDirection { get; set; }

        [JsonPropertyName("satellites")]
        public int? Satellites { get; set; }

        [JsonPropertyName("fix_quality")]
        public int? FixQuality { get; set; }

        [JsonPropertyName("hdop")]
        public double? Hdop { get; set; }

        [JsonPropertyName("status")]
        public string? Status { get; set; }

        [JsonPropertyName("device_id")]
        public string? DeviceId { get; set; }

        public static string GetDirection(double? degrees)
        {
            if (!degrees.HasValue) return string.Empty;

            string[] directions = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                               "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" };
            int index = (int)Math.Round(degrees.Value / 22.5) % 16;
            return directions[index];
        }
    }
}
