using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace Alusekis.Api.Data;

/// <summary>Stores DateTime values as UTC and marks values read back as <see cref="DateTimeKind.Utc"/>.</summary>
public sealed class UtcDateTimeConverter() : ValueConverter<DateTime, DateTime>(
    value => ToUtc(value),
    value => DateTime.SpecifyKind(value, DateTimeKind.Utc))
{
    private static DateTime ToUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };
}
