import '../../core/utils/date_format.dart';

/// Longest comment the server accepts, in characters.
const int maxReportCommentLength = 500;

/// Why a price is reported. [apiName] is what the server expects.
enum ReportReason {
  wrongPrice('WrongPrice', 'Neteisinga kaina'),
  differentProduct('DifferentProduct', 'Kitas produktas'),
  outdatedData('OutdatedData', 'Pasenę duomenys'),
  other('Other', 'Kita');

  const ReportReason(this.apiName, this.label);

  final String apiName;

  /// Lithuanian text shown to the user.
  final String label;
}

/// The price a report is about, known before the form opens.
class ReportTarget {
  const ReportTarget({
    required this.priceEntryId,
    required this.productName,
    required this.volumeMl,
    required this.storeName,
    required this.priceCents,
    required this.observedAt,
  });

  final int priceEntryId;
  final String productName;
  final int volumeMl;
  final String storeName;

  /// Whole euro cents.
  final int priceCents;

  /// When the price was seen in the store (UTC).
  final DateTime observedAt;
}

/// The server's answer to a stored report. Nothing about who sent it.
class SubmittedReport {
  const SubmittedReport({required this.reportId, required this.status, required this.submittedAt});

  factory SubmittedReport.fromJson(Map<String, dynamic> json) => SubmittedReport(
        reportId: (json['reportId'] as num).toInt(),
        status: json['status'] as String,
        submittedAt: parseServerDateTime(json['submittedAt'] as String),
      );

  final int reportId;
  final String status;
  final DateTime submittedAt;
}

/// Result of checking the form: either a valid report or messages for the fields.
class ReportInput {
  const ReportInput.valid(ReportReason this.reason, this.comment)
      : reasonError = null,
        commentError = null;

  const ReportInput.invalid({this.reasonError, this.commentError})
      : reason = null,
        comment = null;

  final ReportReason? reason;

  /// Trimmed; null when empty.
  final String? comment;

  final String? reasonError;
  final String? commentError;

  bool get isValid => reason != null;
}

/// Checks the form like the server does: a reason is required, "Kita" needs a
/// comment, and no comment is longer than [maxReportCommentLength] characters.
ReportInput checkReportInput(ReportReason? reason, String rawComment) {
  final comment = rawComment.trim();

  String? reasonError;
  String? commentError;
  if (reason == null) {
    reasonError = 'Pasirinkite priežastį.';
  }
  if (reason == ReportReason.other && comment.isEmpty) {
    commentError = 'Aprašykite problemą, kai pasirenkate „Kita“.';
  } else if (comment.length > maxReportCommentLength) {
    commentError = 'Komentaras negali būti ilgesnis nei $maxReportCommentLength simbolių.';
  }

  if (reasonError != null || commentError != null) {
    return ReportInput.invalid(reasonError: reasonError, commentError: commentError);
  }
  return ReportInput.valid(reason!, comment.isEmpty ? null : comment);
}
