using Alusekis.Api.Data;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

/// <summary>A migrated SQLite database in a temporary file, deleted on dispose.</summary>
public sealed class TestDatabase : IDisposable
{
    private readonly string _path = Path.Combine(Path.GetTempPath(), $"alusekis-test-{Guid.NewGuid():N}.db");

    public TestDatabase()
    {
        using var db = CreateContext();
        db.Database.Migrate();
    }

    public string ConnectionString => $"Data Source={_path}";

    public AppDbContext CreateContext() =>
        new(new DbContextOptionsBuilder<AppDbContext>().UseAlusekisSqlite(ConnectionString).Options);

    public void Dispose()
    {
        SqliteConnection.ClearAllPools();
        foreach (var file in new[] { _path, _path + "-wal", _path + "-shm" })
        {
            try
            {
                File.Delete(file);
            }
            catch (IOException)
            {
                // Best effort; temp files are harmless.
            }
        }
    }
}
