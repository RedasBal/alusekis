using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Alusekis.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPriceSubmission : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "RequestFingerprint",
                table: "RequestResults",
                type: "TEXT",
                maxLength: 64,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<bool>(
                name: "IsLargeChange",
                table: "PriceEntries",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);

            // IsLargeChange is part of the recorded price: immutable like the other columns.
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_NoUpdate";""");
            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_NoUpdate"
                BEFORE UPDATE OF "ProductId", "StoreId", "PriceCents", "ObservedAt", "CreatedAt", "IsLargeChange", "Id"
                ON "PriceEntries"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries are immutable; insert a new row instead');
                END;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_NoUpdate";""");
            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_NoUpdate"
                BEFORE UPDATE OF "ProductId", "StoreId", "PriceCents", "ObservedAt", "CreatedAt", "Id"
                ON "PriceEntries"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries are immutable; insert a new row instead');
                END;
                """);

            migrationBuilder.DropColumn(
                name: "RequestFingerprint",
                table: "RequestResults");

            migrationBuilder.DropColumn(
                name: "IsLargeChange",
                table: "PriceEntries");
        }
    }
}
