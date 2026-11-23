using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Data;

public static class SqliteSetup
{
    /// <summary>
    /// Configures SQLite for <see cref="AppDbContext"/>. Foreign key enforcement is forced on
    /// regardless of what the configured connection string says.
    /// </summary>
    public static TBuilder UseAlusekisSqlite<TBuilder>(this TBuilder options, string connectionString)
        where TBuilder : DbContextOptionsBuilder
    {
        var builder = new SqliteConnectionStringBuilder(connectionString) { ForeignKeys = true };
        options.UseSqlite(builder.ConnectionString);
        return options;
    }
}
