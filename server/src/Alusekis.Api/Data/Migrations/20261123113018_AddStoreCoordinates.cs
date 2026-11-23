using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Alusekis.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddStoreCoordinates : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<double>(
                name: "Latitude",
                table: "Stores",
                type: "REAL",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "Longitude",
                table: "Stores",
                type: "REAL",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Stores_Latitude_Longitude",
                table: "Stores",
                columns: new[] { "Latitude", "Longitude" });

            migrationBuilder.AddCheckConstraint(
                name: "CK_Stores_Latitude",
                table: "Stores",
                sql: "\"Latitude\" IS NULL OR \"Latitude\" BETWEEN -90 AND 90");

            migrationBuilder.AddCheckConstraint(
                name: "CK_Stores_Longitude",
                table: "Stores",
                sql: "\"Longitude\" IS NULL OR \"Longitude\" BETWEEN -180 AND 180");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Stores_Latitude_Longitude",
                table: "Stores");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Stores_Latitude",
                table: "Stores");

            migrationBuilder.DropCheckConstraint(
                name: "CK_Stores_Longitude",
                table: "Stores");

            migrationBuilder.DropColumn(
                name: "Latitude",
                table: "Stores");

            migrationBuilder.DropColumn(
                name: "Longitude",
                table: "Stores");
        }
    }
}
