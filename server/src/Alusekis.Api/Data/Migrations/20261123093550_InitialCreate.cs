using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Alusekis.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Cities",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Name = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    NormalizedName = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Cities", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DeletionMarkers",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    EntityType = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    EntityId = table.Column<long>(type: "INTEGER", nullable: false),
                    DeletedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DeletionMarkers", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Email = table.Column<string>(type: "TEXT", maxLength: 254, nullable: false),
                    NormalizedEmail = table.Column<string>(type: "TEXT", maxLength: 254, nullable: false),
                    DisplayName = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    PasswordHash = table.Column<string>(type: "TEXT", maxLength: 256, nullable: true),
                    Role = table.Column<int>(type: "INTEGER", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.Id);
                    table.CheckConstraint("CK_Users_Role", "\"Role\" IN (0, 1, 2)");
                });

            migrationBuilder.CreateTable(
                name: "Stores",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    CityId = table.Column<long>(type: "INTEGER", nullable: false),
                    Name = table.Column<string>(type: "TEXT", maxLength: 150, nullable: false),
                    Address = table.Column<string>(type: "TEXT", maxLength: 250, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Stores", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Stores_Cities_CityId",
                        column: x => x.CityId,
                        principalTable: "Cities",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "AuditEntries",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    ActorUserId = table.Column<long>(type: "INTEGER", nullable: true),
                    Action = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    EntityType = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    EntityId = table.Column<long>(type: "INTEGER", nullable: true),
                    DetailsJson = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AuditEntries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AuditEntries_Users_ActorUserId",
                        column: x => x.ActorUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Products",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Name = table.Column<string>(type: "TEXT", maxLength: 150, nullable: false),
                    NormalizedName = table.Column<string>(type: "TEXT", maxLength: 150, nullable: false),
                    VolumeMl = table.Column<int>(type: "INTEGER", nullable: false),
                    Brand = table.Column<string>(type: "TEXT", maxLength: 100, nullable: true),
                    CreatedByUserId = table.Column<long>(type: "INTEGER", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Products", x => x.Id);
                    table.CheckConstraint("CK_Products_VolumeMl", "\"VolumeMl\" BETWEEN 1 AND 50000");
                    table.ForeignKey(
                        name: "FK_Products_Users_CreatedByUserId",
                        column: x => x.CreatedByUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "RequestResults",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    UserId = table.Column<long>(type: "INTEGER", nullable: false),
                    IdempotencyKey = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    StatusCode = table.Column<int>(type: "INTEGER", nullable: false),
                    ResponseJson = table.Column<string>(type: "TEXT", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RequestResults", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RequestResults_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Sessions",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    UserId = table.Column<long>(type: "INTEGER", nullable: false),
                    TokenHash = table.Column<string>(type: "TEXT", maxLength: 128, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    RevokedAt = table.Column<DateTime>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Sessions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Sessions_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PriceEntries",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    ProductId = table.Column<long>(type: "INTEGER", nullable: false),
                    StoreId = table.Column<long>(type: "INTEGER", nullable: false),
                    SubmittedByUserId = table.Column<long>(type: "INTEGER", nullable: true),
                    PriceCents = table.Column<int>(type: "INTEGER", nullable: false),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    ObservedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PriceEntries", x => x.Id);
                    table.CheckConstraint("CK_PriceEntries_PriceCents", "\"PriceCents\" BETWEEN 1 AND 50000");
                    table.CheckConstraint("CK_PriceEntries_Status", "\"Status\" IN (0, 1, 2)");
                    table.ForeignKey(
                        name: "FK_PriceEntries_Products_ProductId",
                        column: x => x.ProductId,
                        principalTable: "Products",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PriceEntries_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PriceEntries_Users_SubmittedByUserId",
                        column: x => x.SubmittedByUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "Reports",
                columns: table => new
                {
                    Id = table.Column<long>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    PriceEntryId = table.Column<long>(type: "INTEGER", nullable: false),
                    ReporterUserId = table.Column<long>(type: "INTEGER", nullable: false),
                    Reason = table.Column<int>(type: "INTEGER", nullable: false),
                    Comment = table.Column<string>(type: "TEXT", maxLength: 1000, nullable: true),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    SubmittedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    ResolvedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    ResolvedByUserId = table.Column<long>(type: "INTEGER", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Reports", x => x.Id);
                    table.CheckConstraint("CK_Reports_Reason", "\"Reason\" IN (0, 1, 2, 3)");
                    table.CheckConstraint("CK_Reports_Status", "\"Status\" IN (0, 1, 2)");
                    table.ForeignKey(
                        name: "FK_Reports_PriceEntries_PriceEntryId",
                        column: x => x.PriceEntryId,
                        principalTable: "PriceEntries",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Reports_Users_ReporterUserId",
                        column: x => x.ReporterUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Reports_Users_ResolvedByUserId",
                        column: x => x.ResolvedByUserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AuditEntries_ActorUserId",
                table: "AuditEntries",
                column: "ActorUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AuditEntries_CreatedAt",
                table: "AuditEntries",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_AuditEntries_EntityType_EntityId",
                table: "AuditEntries",
                columns: new[] { "EntityType", "EntityId" });

            migrationBuilder.CreateIndex(
                name: "IX_Cities_NormalizedName",
                table: "Cities",
                column: "NormalizedName",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DeletionMarkers_DeletedAt_Id",
                table: "DeletionMarkers",
                columns: new[] { "DeletedAt", "Id" });

            migrationBuilder.CreateIndex(
                name: "IX_DeletionMarkers_EntityType_EntityId",
                table: "DeletionMarkers",
                columns: new[] { "EntityType", "EntityId" });

            migrationBuilder.CreateIndex(
                name: "IX_PriceEntries_Product_Store_Status_ObservedAt_Id",
                table: "PriceEntries",
                columns: new[] { "ProductId", "StoreId", "Status", "ObservedAt", "Id" });

            migrationBuilder.CreateIndex(
                name: "IX_PriceEntries_StoreId",
                table: "PriceEntries",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_PriceEntries_SubmittedByUserId",
                table: "PriceEntries",
                column: "SubmittedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Products_CreatedByUserId",
                table: "Products",
                column: "CreatedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Products_NormalizedName_VolumeMl",
                table: "Products",
                columns: new[] { "NormalizedName", "VolumeMl" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Reports_PriceEntryId",
                table: "Reports",
                column: "PriceEntryId");

            migrationBuilder.CreateIndex(
                name: "IX_Reports_ReporterUserId",
                table: "Reports",
                column: "ReporterUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Reports_ResolvedByUserId",
                table: "Reports",
                column: "ResolvedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Reports_Status_SubmittedAt",
                table: "Reports",
                columns: new[] { "Status", "SubmittedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_RequestResults_CreatedAt",
                table: "RequestResults",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_RequestResults_UserId_IdempotencyKey",
                table: "RequestResults",
                columns: new[] { "UserId", "IdempotencyKey" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Sessions_TokenHash",
                table: "Sessions",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Sessions_UserId",
                table: "Sessions",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_Stores_CityId_Name_Address",
                table: "Stores",
                columns: new[] { "CityId", "Name", "Address" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Users_NormalizedEmail",
                table: "Users",
                column: "NormalizedEmail",
                unique: true);

            // Price history is append-only: only Status (moderation) may change after insert,
            // and rows are never deleted. Mirrors the check in AppDbContext.SaveChanges.
            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_NoUpdate"
                BEFORE UPDATE OF "ProductId", "StoreId", "SubmittedByUserId", "PriceCents", "ObservedAt", "CreatedAt", "Id"
                ON "PriceEntries"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries are immutable; insert a new row instead');
                END;
                """);

            migrationBuilder.Sql("""
                CREATE TRIGGER "TR_PriceEntries_NoDelete"
                BEFORE DELETE ON "PriceEntries"
                BEGIN
                    SELECT RAISE(ABORT, 'PriceEntries cannot be deleted');
                END;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_NoDelete";""");
            migrationBuilder.Sql("""DROP TRIGGER IF EXISTS "TR_PriceEntries_NoUpdate";""");

            migrationBuilder.DropTable(
                name: "AuditEntries");

            migrationBuilder.DropTable(
                name: "DeletionMarkers");

            migrationBuilder.DropTable(
                name: "Reports");

            migrationBuilder.DropTable(
                name: "RequestResults");

            migrationBuilder.DropTable(
                name: "Sessions");

            migrationBuilder.DropTable(
                name: "PriceEntries");

            migrationBuilder.DropTable(
                name: "Products");

            migrationBuilder.DropTable(
                name: "Stores");

            migrationBuilder.DropTable(
                name: "Users");

            migrationBuilder.DropTable(
                name: "Cities");
        }
    }
}
