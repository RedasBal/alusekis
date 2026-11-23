using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Alusekis.Api.Data;

/// <summary>Used only by `dotnet ef` (migrations); the running app configures the context in Program.</summary>
public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseAlusekisSqlite("Data Source=alusekis.design.db")
            .Options;

        return new AppDbContext(options);
    }
}
