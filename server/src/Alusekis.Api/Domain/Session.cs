namespace Alusekis.Api.Domain;

/// <summary>A login session. Only a hash of the token is stored.</summary>
public class Session
{
    public long Id { get; set; }

    public long UserId { get; set; }

    public User User { get; set; } = null!;

    public required string TokenHash { get; set; }

    public DateTime CreatedAt { get; set; }

    public DateTime ExpiresAt { get; set; }

    public DateTime? RevokedAt { get; set; }
}
