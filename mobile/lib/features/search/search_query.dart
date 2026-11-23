/// Shortest and longest search text the server accepts (after trimming).
const int minSearchLength = 2;
const int maxSearchLength = 100;

/// How long the user must stop typing before a request is sent.
const Duration searchDebounce = Duration(milliseconds: 300);

/// Hint shown while there is nothing to search for yet.
const String searchHint = 'Įveskite bent $minSearchLength simbolius';

/// The text that is sent: without leading and trailing spaces.
String searchText(String raw) => raw.trim();

/// Whether [raw] may be sent to the server. Anything shorter than 2 characters
/// (after trimming) is never sent; the screen shows [searchHint] instead.
bool isSearchable(String raw) {
  final length = searchText(raw).length;
  return length >= minSearchLength && length <= maxSearchLength;
}
