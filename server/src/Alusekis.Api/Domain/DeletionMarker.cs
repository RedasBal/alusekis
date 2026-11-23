namespace Alusekis.Api.Domain;

/// <summary>
/// Tombstone for a deleted entity so offline clients can remove it on the next sync
/// ("what was deleted since time X").
/// </summary>
public class DeletionMarker
{
    public long Id { get; set; }

    public required string EntityType { get; set; }

    public long EntityId { get; set; }

    public DateTime DeletedAt { get; set; }
}
