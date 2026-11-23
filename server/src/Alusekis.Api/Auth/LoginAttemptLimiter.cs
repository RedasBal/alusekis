using System.Collections.Concurrent;

namespace Alusekis.Api.Auth;

/// <summary>
/// Allows <see cref="AuthRules.MaxFailedLogins"/> failed attempts per account key within
/// <see cref="AuthRules.FailedLoginWindow"/>. Keyed by normalized e-mail, including unknown
/// addresses, so a lock-out reveals nothing about which accounts exist.
/// State is in memory (single server instance); it resets on restart.
/// </summary>
public sealed class LoginAttemptLimiter(TimeProvider clock)
{
    private static readonly TimeSpan PurgeInterval = TimeSpan.FromMinutes(1);

    private readonly ConcurrentDictionary<string, List<DateTime>> _failures = new();
    private DateTime _lastPurge = DateTime.MinValue;

    public bool IsLocked(string key, out TimeSpan retryAfter)
    {
        var now = Now();
        Purge(now);
        retryAfter = TimeSpan.Zero;

        if (!_failures.TryGetValue(key, out var attempts))
        {
            return false;
        }

        lock (attempts)
        {
            attempts.RemoveAll(t => now - t >= AuthRules.FailedLoginWindow);
            if (attempts.Count < AuthRules.MaxFailedLogins)
            {
                return false;
            }

            retryAfter = attempts[0] + AuthRules.FailedLoginWindow - now;
            return true;
        }
    }

    public void RecordFailure(string key)
    {
        var attempts = _failures.GetOrAdd(key, _ => []);
        lock (attempts)
        {
            attempts.Add(Now());
        }
    }

    public void Reset(string key) => _failures.TryRemove(key, out _);

    private DateTime Now() => clock.GetUtcNow().UtcDateTime;

    /// <summary>Drops expired entries so random e-mail guesses cannot grow memory without bound.</summary>
    private void Purge(DateTime now)
    {
        if (now - _lastPurge < PurgeInterval)
        {
            return;
        }

        _lastPurge = now;
        foreach (var entry in _failures)
        {
            lock (entry.Value)
            {
                entry.Value.RemoveAll(t => now - t >= AuthRules.FailedLoginWindow);
                if (entry.Value.Count == 0)
                {
                    _failures.TryRemove(entry);
                }
            }
        }
    }
}
