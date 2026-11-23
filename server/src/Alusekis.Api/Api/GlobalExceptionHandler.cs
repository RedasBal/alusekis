using Microsoft.AspNetCore.Diagnostics;

namespace Alusekis.Api.Api;

/// <summary>
/// Turns any unhandled exception into an <see cref="ErrorDto"/>. Internal details
/// (messages, stack traces) are logged, never returned to the client.
/// </summary>
internal sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken cancellationToken)
    {
        switch (exception)
        {
            // Malformed JSON, missing required parameters, body too large, ...
            case BadHttpRequestException badRequest:
                logger.LogInformation(exception, "Bad request {RequestId}", context.TraceIdentifier);
                await ErrorResponses.WriteAsync(
                    context,
                    badRequest.StatusCode,
                    ErrorCodes.ForStatus(badRequest.StatusCode),
                    "The request is malformed or missing required data.");
                return true;

            // The client went away; nobody is listening for a response.
            case OperationCanceledException when context.RequestAborted.IsCancellationRequested:
                logger.LogInformation("Request {RequestId} was cancelled by the client", context.TraceIdentifier);
                return true;

            default:
                logger.LogError(exception, "Unhandled exception for request {RequestId}", context.TraceIdentifier);
                await ErrorResponses.WriteAsync(
                    context,
                    StatusCodes.Status500InternalServerError,
                    ErrorCodes.InternalError,
                    "An unexpected error occurred.");
                return true;
        }
    }
}
