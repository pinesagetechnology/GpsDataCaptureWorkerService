using System.Globalization;

namespace GpsDataCaptureWorkerService.GPSProcessing
{
    public class NmeaSentenceParser
    {
        public static NmeaSentence? Parse(string sentence)
        {
            if (string.IsNullOrWhiteSpace(sentence) || !sentence.StartsWith("$"))
                return null;

            // Validate checksum if present
            if (sentence.Contains('*'))
            {
                if (!ValidateChecksum(sentence))
                    return null;
            }

            // Remove checksum for parsing
            var data = sentence.Split('*')[0];
            var fields = data.Split(',');

            if (fields.Length < 2)
                return null;

            var messageType = fields[0].TrimStart('$');

            return messageType switch
            {
                "GPRMC" or "GNRMC" => ParseRMC(fields),
                "GPGGA" or "GNGGA" => ParseGGA(fields),
                "GPVTG" or "GNVTG" => ParseVTG(fields),
                _ => null
            };
        }

        private static bool ValidateChecksum(string sentence)
        {
            try
            {
                var parts = sentence.Split('*');
                if (parts.Length != 2)
                    return false;

                var data = parts[0].TrimStart('$');
                var checksumHex = parts[1].Substring(0, 2);
                var expectedChecksum = Convert.ToByte(checksumHex, 16);

                byte calculatedChecksum = 0;
                foreach (var c in data)
                {
                    calculatedChecksum ^= (byte)c;
                }

                return calculatedChecksum == expectedChecksum;
            }
            catch
            {
                return false;
            }
        }

        private static RMCSentence? ParseRMC(string[] fields)
        {
            // $GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A
            // Format: $GPRMC,time,status,lat,NS,lon,EW,speed,course,date,magvar,magvarEW*checksum
            if (fields.Length < 10)
                return null;

            try
            {
                return new RMCSentence
                {
                    Time = ParseTime(fields[1]),
                    Status = fields[2],
                    Latitude = ParseLatitude(fields[3], fields[4]),
                    Longitude = ParseLongitude(fields[5], fields[6]),
                    SpeedKnots = ParseDouble(fields[7]),
                    Course = ParseDouble(fields[8]),
                    Date = ParseDate(fields[9])
                };
            }
            catch
            {
                return null;
            }
        }

        private static GGASentence? ParseGGA(string[] fields)
        {
            // $GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47
            // Format: $GPGGA,time,lat,NS,lon,EW,quality,sats,hdop,alt,M,geoid,M,dgps_age,dgps_id*checksum
            if (fields.Length < 13)
                return null;

            try
            {
                return new GGASentence
                {
                    Time = ParseTime(fields[1]),
                    Latitude = ParseLatitude(fields[2], fields[3]),
                    Longitude = ParseLongitude(fields[4], fields[5]),
                    Quality = ParseInt(fields[6]),
                    Satellites = ParseInt(fields[7]),
                    HDOP = ParseDouble(fields[8]),
                    Altitude = ParseDouble(fields[9])
                };
            }
            catch
            {
                return null;
            }
        }

        private static VTGSentence? ParseVTG(string[] fields)
        {
            // $GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*48
            // Format: $GPVTG,course_true,T,course_mag,M,speed_knots,N,speed_kmh,K*checksum
            if (fields.Length < 9)
                return null;

            try
            {
                return new VTGSentence
                {
                    CourseTrue = ParseDouble(fields[1]),
                    CourseMagnetic = ParseDouble(fields[3]),
                    SpeedKnots = ParseDouble(fields[5]),
                    SpeedKmh = ParseDouble(fields[7])
                };
            }
            catch
            {
                return null;
            }
        }

        private static TimeSpan? ParseTime(string time)
        {
            if (string.IsNullOrWhiteSpace(time) || time.Length < 6)
                return null;

            try
            {
                var hours = int.Parse(time.Substring(0, 2));
                var minutes = int.Parse(time.Substring(2, 2));
                var seconds = int.Parse(time.Substring(4, 2));
                var milliseconds = time.Length > 7 ? int.Parse(time.Substring(7)) * 100 : 0;

                return new TimeSpan(0, hours, minutes, seconds, milliseconds);
            }
            catch
            {
                return null;
            }
        }

        private static DateTime? ParseDate(string date)
        {
            if (string.IsNullOrWhiteSpace(date) || date.Length < 6)
                return null;

            try
            {
                var day = int.Parse(date.Substring(0, 2));
                var month = int.Parse(date.Substring(2, 2));
                var year = int.Parse(date.Substring(4, 2)) + 2000;

                return new DateTime(year, month, day);
            }
            catch
            {
                return null;
            }
        }

        private static double? ParseLatitude(string lat, string ns)
        {
            if (string.IsNullOrWhiteSpace(lat) || lat.Length < 4)
                return null;

            try
            {
                // Format: ddmm.mmmm
                var degrees = int.Parse(lat.Substring(0, 2));
                var minutes = double.Parse(lat.Substring(2), CultureInfo.InvariantCulture);
                var decimalDegrees = degrees + (minutes / 60.0);

                return ns == "S" ? -decimalDegrees : decimalDegrees;
            }
            catch
            {
                return null;
            }
        }

        private static double? ParseLongitude(string lon, string ew)
        {
            if (string.IsNullOrWhiteSpace(lon) || lon.Length < 5)
                return null;

            try
            {
                // Format: dddmm.mmmm
                var degrees = int.Parse(lon.Substring(0, 3));
                var minutes = double.Parse(lon.Substring(3), CultureInfo.InvariantCulture);
                var decimalDegrees = degrees + (minutes / 60.0);

                return ew == "W" ? -decimalDegrees : decimalDegrees;
            }
            catch
            {
                return null;
            }
        }

        private static double? ParseDouble(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return null;

            return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var result)
                ? result
                : null;
        }

        private static int? ParseInt(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return null;

            return int.TryParse(value, out var result) ? result : null;
        }
    }
}
