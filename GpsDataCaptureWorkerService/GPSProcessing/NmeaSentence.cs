namespace GpsDataCaptureWorkerService.GPSProcessing
{
    public abstract class NmeaSentence
    {
        public TimeSpan? Time { get; set; }
    }

    public class RMCSentence : NmeaSentence
    {
        public string? Status { get; set; }
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public double? SpeedKnots { get; set; }
        public double? Course { get; set; }
        public DateTime? Date { get; set; }
    }

    public class GGASentence : NmeaSentence
    {
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public int? Quality { get; set; }
        public int? Satellites { get; set; }
        public double? HDOP { get; set; }
        public double? Altitude { get; set; }
    }

    public class VTGSentence : NmeaSentence
    {
        public double? CourseTrue { get; set; }
        public double? CourseMagnetic { get; set; }
        public double? SpeedKnots { get; set; }
        public double? SpeedKmh { get; set; }
    }
}
