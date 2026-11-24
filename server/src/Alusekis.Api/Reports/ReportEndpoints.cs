using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Prices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using HttpJsonOptions = Microsoft.AspNetCore.Http.Json.JsonOptions;

namespace Alusekis.Api.Reports;

/// <param name="Reason">One of <see cref="ReportReason"/> by name (e.g. "WrongPrice").</param>
/// <param name="Comment">Optional, up to 500 characters; required when the reason is "Other".</param>
/// <param name="IdempotencyKey">Chosen by the client (e.g. a UUID) and reused for retries of the same report.</param>
public sealed record SubmitReportRequest(
    long? PriceEntryId,
    string? Reason,
    string? Comment,
    string? IdempotencyKey);

/// <summary>What the reporter gets back. Nothing about who they are beyond what they sent.</summary>
public sealed record SubmittedReportDto(long ReportId, ReportStatus Status, DateTime SubmittedAt);

/// <summary>
/// <c>POST /api/v1/reports</c>: a signed-in User or Admin reports a price entry as doubtful.
/// A report never changes the price and never hides it; a moderator decides later.
/// </summary>
public static class ReportEndpoints
{
    public static RouteGroupBuilder MapReports(this RouteGroupBuilder v1)
    {
        // Guests: 401 when not signed in, 403 for the Guest role (checked only here, on the server).
        v1.MapPost("/reports", Submit).RequireAuthorization(Policies.User);
        return v1;
    }

    private static async Task<IResult> Submit(
        SubmitReportRequest request,
        HttpContext http,
        AppDbContext db,
        TimeProvider clock,
        IOptions<HttpJsonOptions> jsonOptions,
        CancellationToken ct)
    {
        // ---- input (nothing is written when it is wrong) ----
        var key = request.IdempotencyKey;
        if (string.IsNullOrWhiteSpace(key) || key.Length > PriceEndpoints.MaxIdempotencyKeyLength)
        {
            return Invalid(http, $"idempotencyKey is required (1-{PriceEndpoints.MaxIdempotencyKeyLength} characters).");
        }

        if (request.PriceEntryId is not { } priceEntryId)
        {
            return Invalid(http, "priceEntryId is required.");
        }

        if (!TryParseReason(request.Reason, out var reason))
        {
            return Invalid(http, "reason must be one of: " + string.Join(", ", Enum.GetNames<ReportReason>()) + ".");
        }

        var comment = request.Comment?.Trim();
        if (string.IsNullOrEmpty(comment))
        {
            comment = null;
        }

        if (comment is { Length: > DomainLimits.MaxReportCommentLength })
        {
            return Invalid(http, $"comment must be at most {DomainLimits.MaxReportCommentLength} characters.");
        }

        if (reason == ReportReason.Other && comment is null)
        {
            return Invalid(http, "comment is required when the reason is Other.");
        }

        var userId = http.User.GetUserId();
        var fingerprint = Fingerprint(priceEntryId, reason, comment);

        // ---- a retry of an earlier successful request: answer it again, create nothing ----
        if (await PriceEndpoints.ReplayAsync(http, db, userId, key, fingerprint, ct) is { } replayed)
        {
            return replayed;
        }

        if (!await db.PriceEntries.AnyAsync(p => p.Id == priceEntryId, ct))
        {
            return ErrorResponses.Result(
                http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Price entry not found.");
        }

        // ---- one transaction: report + stored result, all or nothing ----
        var now = clock.GetUtcNow().UtcDateTime;
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Only the report is added: the price entry is not touched.
        var report = new Report
        {
            PriceEntryId = priceEntryId,
            ReporterUserId = userId,
            Reason = reason,
            Comment = comment,
            Status = ReportStatus.New,
            SubmittedAt = now,
        };
        db.Reports.Add(report);

        try
        {
            await db.SaveChangesAsync(ct); // to get the id; not committed yet

            var responseJson = JsonSerializer.Serialize(
                new SubmittedReportDto(report.Id, report.Status, report.SubmittedAt),
                jsonOptions.Value.SerializerOptions);
            db.RequestResults.Add(new RequestResult
            {
                UserId = userId,
                IdempotencyKey = key,
                RequestFingerprint = fingerprint,
                StatusCode = StatusCodes.Status201Created,
                ResponseJson = responseJson,
                CreatedAt = now,
            });
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return Results.Text(responseJson, "application/json", Encoding.UTF8, StatusCodes.Status201Created);
        }
        catch (DbUpdateException ex) when (PriceEndpoints.IsUniqueViolation(ex))
        {
            // A concurrent request with the same key won: undo ours and answer like a retry.
            await transaction.RollbackAsync(ct);
            db.ChangeTracker.Clear();
            return await PriceEndpoints.ReplayAsync(http, db, userId, key, fingerprint, ct)
                ?? ErrorResponses.Result(
                    http, StatusCodes.Status409Conflict, ErrorCodes.Conflict, "The request conflicted with another one.");
        }
    }

    /// <summary>
    /// Accepts the names of <see cref="ReportReason"/> only: "3" or an unknown word is not a reason.
    /// </summary>
    private static bool TryParseReason(string? text, out ReportReason reason)
    {
        reason = default;
        var name = text?.Trim();
        return !string.IsNullOrEmpty(name)
            && !char.IsDigit(name[0])
            && name[0] != '-'
            && Enum.TryParse(name, ignoreCase: true, out reason)
            && Enum.IsDefined(reason);
    }

    /// <summary>What makes two requests "the same": the fields that decide what is recorded.</summary>
    private static string Fingerprint(long priceEntryId, ReportReason reason, string? comment)
    {
        var canonical = string.Join('|', "report", priceEntryId, (int)reason, comment ?? string.Empty);
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }

    private static IResult Invalid(HttpContext http, string message) =>
        ErrorResponses.Result(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.ValidationFailed, message);
}
