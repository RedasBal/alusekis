namespace Alusekis.Api.Domain;

/// <summary>Append-only record of a significant action (moderation, admin changes, ...).</summary>
public class AuditEntry
{
    public long Id { get; set; }

    /// <summary>Null for system actions.</summary>
    public long? ActorUserId { get; set; }

    public User? ActorUser { get; set; }

    public required string Action { get; set; }

    public required string EntityType { get; set; }

    public long? EntityId { get; set; }

    /// <summary>Optional JSON with action details.</summary>
    public string? DetailsJson { get; set; }

    public DateTime CreatedAt { get; set; }
}
