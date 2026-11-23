namespace Alusekis.Api.Data;

/// <summary>Thrown when code tries to change or delete an existing price history row.</summary>
public sealed class PriceHistoryImmutableException(string message) : InvalidOperationException(message);
