namespace Alusekis.Api.Auth;

/// <summary>Outgoing e-mail. Hides the transport (SMTP, API, ...) from the rest of the server.</summary>
public interface IEmailSender
{
    Task SendPasswordResetAsync(string toEmail, string resetLink, CancellationToken cancellationToken);
}

/// <summary>
/// Development stand-in that writes the reset link to the log instead of sending a message.
/// The link contains a secret; replace this with a real sender before production.
/// </summary>
public sealed class ConsoleEmailSender(ILogger<ConsoleEmailSender> logger) : IEmailSender
{
    public Task SendPasswordResetAsync(string toEmail, string resetLink, CancellationToken cancellationToken)
    {
        logger.LogInformation("[DEV e-mail] Password reset for {Email}: {Link}", toEmail, resetLink);
        return Task.CompletedTask;
    }
}
