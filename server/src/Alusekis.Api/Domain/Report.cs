namespace Alusekis.Api.Domain;

/// <summary>A user's report that a price entry is wrong.</summary>
public class Report
{
    public long Id { get; set; }

    public long PriceEntryId { get; set; }

    public PriceEntry PriceEntry { get; set; } = null!;

    /// <summary>Null after the reporter deleted their account.</summary>
    public long? ReporterUserId { get; set; }

    public User? Reporter { get; set; }

    public ReportReason Reason { get; set; }

    public string? Comment { get; set; }

    public ReportStatus Status { get; set; } = ReportStatus.New;

    public DateTime SubmittedAt { get; set; }

    public DateTime? ResolvedAt { get; set; }

    public long? ResolvedByUserId { get; set; }

    public User? ResolvedBy { get; set; }
}
