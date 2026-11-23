using Microsoft.AspNetCore.WebUtilities;

namespace Alusekis.Api.Api;

/// <summary>Stable error codes clients may switch on. Never rename an existing code.</summary>
public static class ErrorCodes
{
    public const string BadRequest = "bad_request";
    public const string ValidationFailed = "validation_failed";
    public const string Unauthorized = "unauthorized";
    public const string Forbidden = "forbidden";
    public const string NotFound = "not_found";
    public const string MethodNotAllowed = "method_not_allowed";
    public const string Conflict = "conflict";
    public const string PayloadTooLarge = "payload_too_large";
    public const string UnsupportedMediaType = "unsupported_media_type";
    public const string TooManyRequests = "too_many_requests";
    public const string InternalError = "internal_error";
    public const string ServiceUnavailable = "service_unavailable";
    public const string RequestTimeout = "request_timeout";

    public static string ForStatus(int statusCode) => statusCode switch
    {
        StatusCodes.Status400BadRequest => BadRequest,
        StatusCodes.Status401Unauthorized => Unauthorized,
        StatusCodes.Status403Forbidden => Forbidden,
        StatusCodes.Status404NotFound => NotFound,
        StatusCodes.Status405MethodNotAllowed => MethodNotAllowed,
        StatusCodes.Status409Conflict => Conflict,
        StatusCodes.Status413PayloadTooLarge => PayloadTooLarge,
        StatusCodes.Status415UnsupportedMediaType => UnsupportedMediaType,
        StatusCodes.Status422UnprocessableEntity => ValidationFailed,
        StatusCodes.Status429TooManyRequests => TooManyRequests,
        StatusCodes.Status503ServiceUnavailable => ServiceUnavailable,
        StatusCodes.Status504GatewayTimeout => RequestTimeout,
        >= 500 => InternalError,
        _ => BadRequest,
    };

    public static string DefaultMessage(int statusCode) =>
        statusCode == StatusCodes.Status404NotFound
            ? "The requested resource was not found."
            : ReasonPhrases.GetReasonPhrase(statusCode) is { Length: > 0 } phrase ? phrase + "." : "Request failed.";
}
