using System.ComponentModel.DataAnnotations;

namespace Alusekis.Api.Configuration;

public sealed class DatabaseOptions
{
    /// <summary>Key under "ConnectionStrings"; env var <c>ConnectionStrings__Default</c>.</summary>
    public const string ConnectionStringName = "Default";

    /// <summary>Section for the remaining settings; env vars <c>Database__*</c>.</summary>
    public const string SectionName = "Database";

    [Required(ErrorMessage =
        "Missing required setting 'ConnectionStrings:Default' " +
        "(set it in appsettings or via the environment variable ConnectionStrings__Default).")]
    public string ConnectionString { get; set; } = string.Empty;

    /// <summary>Apply pending EF Core migrations when the server starts.</summary>
    public bool MigrateOnStartup { get; set; }
}
