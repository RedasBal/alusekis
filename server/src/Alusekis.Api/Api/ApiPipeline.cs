using System.Text.Json.Serialization;
using Alusekis.Api.Auth;
using Alusekis.Api.Prices;
using Alusekis.Api.Products;
using Alusekis.Api.Reports;
using Alusekis.Api.Stores;
using Microsoft.AspNetCore.Http.Timeouts;

namespace Alusekis.Api.Api;

public static class ApiPipeline
{
    public const string RoutePrefix = "/api/v1";
    public const string RequestIdHeader = "X-Request-Id";

    /// <summary>Server-side processing limit per request. Not enforced while a debugger is attached.</summary>
    public static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(10);

    public static IServiceCollection AddAlusekisApi(this IServiceCollection services)
    {
        services.AddSingleton(TimeProvider.System);
        services.AddAlusekisPrices();

        // camelCase property names (web default), enums as their names, UTC dates as ISO 8601.
        services.ConfigureHttpJsonOptions(options =>
            options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

        services.AddExceptionHandler<GlobalExceptionHandler>();

        services.AddRequestTimeouts(options =>
        {
            options.DefaultPolicy = new RequestTimeoutPolicy
            {
                Timeout = RequestTimeout,
                TimeoutStatusCode = StatusCodes.Status504GatewayTimeout,
                WriteTimeoutResponse = context => ErrorResponses.WriteAsync(
                    context,
                    StatusCodes.Status504GatewayTimeout,
                    ErrorCodes.RequestTimeout,
                    $"The request did not complete within {RequestTimeout.TotalSeconds:0} seconds."),
            };
        });

        return services;
    }

    public static WebApplication UseAlusekisApi(this WebApplication app)
    {
        app.Use(AssignRequestId);

        // Fallback delegate only runs if GlobalExceptionHandler declines an exception.
        app.UseExceptionHandler(new ExceptionHandlerOptions
        {
            ExceptionHandler = context => ErrorResponses.WriteAsync(
                context,
                StatusCodes.Status500InternalServerError,
                ErrorCodes.InternalError,
                "An unexpected error occurred."),
        });

        // Empty 4xx/5xx responses (unknown route, wrong method, ...) get the standard error body.
        app.UseStatusCodePages(context =>
        {
            var status = context.HttpContext.Response.StatusCode;
            return ErrorResponses.WriteAsync(
                context.HttpContext, status, ErrorCodes.ForStatus(status), ErrorCodes.DefaultMessage(status));
        });

        app.UseRouting();
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRequestTimeouts();

        return app;
    }

    public static RouteGroupBuilder MapApiV1(this IEndpointRouteBuilder endpoints)
    {
        var v1 = endpoints.MapGroup(RoutePrefix);

        v1.MapGet("/ping", (TimeProvider clock) =>
            Results.Ok(new PingResponse("ok", clock.GetUtcNow().UtcDateTime)));

        v1.MapAuth();
        v1.MapStores();
        v1.MapProducts();
        v1.MapPrices();
        v1.MapReports();

        return v1;
    }

    /// <summary>
    /// Uses a well-formed incoming X-Request-Id (so client and server logs correlate) or the
    /// server-generated trace identifier, and echoes it on every response.
    /// </summary>
    private static Task AssignRequestId(HttpContext context, RequestDelegate next)
    {
        if (context.Request.Headers.TryGetValue(RequestIdHeader, out var incoming)
            && incoming.Count == 1
            && IsValidRequestId(incoming[0]))
        {
            context.TraceIdentifier = incoming[0]!;
        }

        context.Response.OnStarting(() =>
        {
            context.Response.Headers[RequestIdHeader] = context.TraceIdentifier;
            return Task.CompletedTask;
        });

        return next(context);
    }

    private static bool IsValidRequestId(string? value) =>
        value is { Length: > 0 and <= 64 }
        && value.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.' or ':');
}

public sealed record PingResponse(string Status, DateTime ServerTime);
