namespace Alusekis.Api.Domain;

// Enum values are persisted as integers. Never renumber existing members.

public enum Role
{
    Guest = 0,
    User = 1,
    Admin = 2,
}

public enum PriceStatus
{
    Pending = 0,
    Approved = 1,
    Rejected = 2,
}

public enum ReportReason
{
    WrongPrice = 0,
    DifferentProduct = 1,
    OutdatedData = 2,
    Other = 3,
}

public enum ReportStatus
{
    New = 0,
    Confirmed = 1,
    Rejected = 2,
}
