namespace Alusekis.Api.Domain;

public class User
{
    public long Id { get; set; }

    public required string Email { get; set; }

    /// <summary>Lookup key, see <see cref="TextNormalizer.NormalizeEmail"/>. Unique.</summary>
    public required string NormalizedEmail { get; set; }

    public required string DisplayName { get; set; }

    /// <summary>Set by the authentication feature; null for accounts without a password.</summary>
    public string? PasswordHash { get; set; }

    /// <summary>SHA-256 (hex) of the single-use password reset token; null when no reset is pending.</summary>
    public string? PasswordResetTokenHash { get; set; }

    public DateTime? PasswordResetExpiresAt { get; set; }

    public Role Role { get; set; } = Role.User;

    public DateTime CreatedAt { get; set; }

    public List<Session> Sessions { get; set; } = [];
}
