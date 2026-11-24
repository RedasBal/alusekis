using Alusekis.Api.Domain;

namespace Alusekis.Api.Prices;

/// <summary>Price rules shared by every way a price can be recorded. Integer arithmetic only.</summary>
public static class PriceRules
{
    /// <summary>Allowed change against the previous valid price, in percent (FR-08).</summary>
    public const int LargeChangePercent = 50;

    public static bool IsValidPrice(int priceCents) =>
        priceCents is >= DomainLimits.MinPriceCents and <= DomainLimits.MaxPriceCents;

    /// <summary>
    /// True when <paramref name="newCents"/> differs from <paramref name="previousCents"/> by more than
    /// 50 %: <c>abs(new - old) * 100 &gt; old * 50</c>. Exactly 50 % is not large. Computed in
    /// <see cref="long"/> so no product can overflow.
    /// </summary>
    public static bool IsLargeChange(int previousCents, int newCents)
    {
        long difference = Math.Abs((long)newCents - previousCents);
        return difference * 100 > (long)previousCents * LargeChangePercent;
    }
}
