namespace Alusekis.Api.Api;

/// <summary>
/// The single error shape returned by every endpoint.
/// <paramref name="Code"/> is a stable machine-readable snake_case code,
/// <paramref name="Message"/> is human-readable, <paramref name="RequestId"/> matches the
/// <c>X-Request-Id</c> response header and server logs.
/// </summary>
public sealed record ErrorDto(string Code, string Message, string RequestId);
