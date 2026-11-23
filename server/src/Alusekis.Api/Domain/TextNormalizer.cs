using System.Globalization;
using System.Text;

namespace Alusekis.Api.Domain;

/// <summary>
/// Produces comparison keys for names: trimmed, single-spaced, lower-case and without
/// diacritics, so "  ŠVYTURYS  Ekstra" and "svyturys ekstra" map to the same key.
/// </summary>
public static class TextNormalizer
{
    public static string NormalizeName(string value)
    {
        ArgumentNullException.ThrowIfNull(value);

        var decomposed = value.Trim().Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        var previousWasSpace = false;

        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark)
            {
                continue;
            }

            if (char.IsWhiteSpace(c))
            {
                if (!previousWasSpace)
                {
                    builder.Append(' ');
                }

                previousWasSpace = true;
                continue;
            }

            builder.Append(char.ToLowerInvariant(c));
            previousWasSpace = false;
        }

        return builder.ToString().Normalize(NormalizationForm.FormC);
    }

    public static string NormalizeEmail(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return value.Trim().ToLowerInvariant();
    }
}
