using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Alusekis.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAuthentication : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "PasswordResetExpiresAt",
                table: "Users",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PasswordResetTokenHash",
                table: "Users",
                type: "TEXT",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AlterColumn<long>(
                name: "ReporterUserId",
                table: "Reports",
                type: "INTEGER",
                nullable: true,
                oldClrType: typeof(long),
                oldType: "INTEGER");

            migrationBuilder.CreateIndex(
                name: "IX_Users_PasswordResetTokenHash",
                table: "Users",
                column: "PasswordResetTokenHash",
                unique: true);

            // Account deletion must be able to clear PriceEntries.SubmittedByUserId (GDPR), but price
            // history stays append-only: the submitter can be removed, never reassigned.
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_NoUpdate";""");
            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_NoUpdate"
                BEFORE UPDATE OF "ProductId", "StoreId", "PriceCents", "ObservedAt", "CreatedAt", "Id"
                ON "PriceEntries"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries are immutable; insert a new row instead');
                END;
                """);
            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_SubmitterOnlyCleared"
                BEFORE UPDATE OF "SubmittedByUserId" ON "PriceEntries"
                WHEN NEW."SubmittedByUserId" IS NOT NULL AND NEW."SubmittedByUserId" IS NOT OLD."SubmittedByUserId"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries are immutable; the submitter can only be cleared');
                END;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_SubmitterOnlyCleared";""");
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_NoUpdate";""");
            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_NoUpdate"
                BEFORE UPDATE OF "ProductId", "StoreId", "SubmittedByUserId", "PriceCents", "ObservedAt", "CreatedAt", "Id"
                ON "PriceEntries"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries are immutable; insert a new row instead');
                END;
                """);

            migrationBuilder.DropIndex(
                name: "IX_Users_PasswordResetTokenHash",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "PasswordResetExpiresAt",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "PasswordResetTokenHash",
                table: "Users");

            migrationBuilder.AlterColumn<long>(
                name: "ReporterUserId",
                table: "Reports",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0L,
                oldClrType: typeof(long),
                oldType: "INTEGER",
                oldNullable: true);
        }
    }
}
