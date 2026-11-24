using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Alusekis.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddReportVersion : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "Version",
                table: "Reports",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0L);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Version",
                table: "Reports");
        }
    }
}
