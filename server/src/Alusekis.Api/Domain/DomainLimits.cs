namespace Alusekis.Api.Domain;

/// <summary>Value ranges shared by validation and database check constraints.</summary>
public static class DomainLimits
{
    /// <summary>Prices are stored as whole euro cents.</summary>
    public const int MinPriceCents = 1;
    public const int MaxPriceCents = 50_000;

    /// <summary>Volumes are stored as whole millilitres.</summary>
    public const int MinVolumeMl = 1;
    public const int MaxVolumeMl = 50_000;

    /// <summary>Longest comment of a report, in characters.</summary>
    public const int MaxReportCommentLength = 500;
}
