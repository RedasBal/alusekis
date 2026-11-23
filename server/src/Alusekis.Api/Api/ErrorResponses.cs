namespace Alusekis.Api.Api;

public static class ErrorResponses
{
    /// <summary>Writes an <see cref="ErrorDto"/> body with the given status code.</summary>
    public static Task WriteAsync(HttpContext context, int statusCode, string code, string message)
    {
        context.Response.StatusCode = statusCode;
        return context.Response.WriteAsJsonAsync(
            new ErrorDto(code, message, context.TraceIdentifier),
            context.RequestAborted);
    }

    /// <summary>Endpoint result carrying an <see cref="ErrorDto"/> for use in minimal API handlers.</summary>
    public static IResult Result(HttpContext context, int statusCode, string code, string message) =>
        Results.Json(new ErrorDto(code, message, context.TraceIdentifier), statusCode: statusCode);
}
