using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace Alusekis.Api.Auth;

/// <summary>Random secrets (access and reset tokens). Only their hash is ever stored.</summary>
public static class Tokens
{
    /// <summary>256 bits from a cryptographic RNG, URL-safe.</summary>
    public static string Generate() => Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));

    /// <summary>SHA-256 as lower-case hex (64 characters). Tokens are high-entropy, so no salt is needed.</summary>
    public static string Hash(string token) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
