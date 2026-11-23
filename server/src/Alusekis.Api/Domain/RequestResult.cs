namespace Alusekis.Api.Domain;

/// <summary>
/// Stored response of an idempotent write request, so a retried request with the same
/// idempotency key returns the original result instead of creating a duplicate.
/// (UserId, IdempotencyKey) is unique.
/// </summary>
public class RequestResult
{
    public long Id { get; set; }

    public long UserId { get; set; }

    public User User { get; set; } = null!;

    public required string IdempotencyKey { get; set; }

    public int StatusCode { get; set; }

    public required string ResponseJson { get; set; }

    public DateTime CreatedAt { get; set; }
}
