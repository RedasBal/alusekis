import 'package:alusekis/core/utils/debouncer.dart';
import 'package:alusekis/features/search/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSearchable', () {
    test('needs at least 2 characters after trimming', () {
      for (final text in ['', ' ', '   ', 'a', '  a  ', 'ž', '\t\n']) {
        expect(isSearchable(text), isFalse, reason: '"$text"');
      }
      for (final text in ['ab', '  ab  ', 'žv', 'Švyturys']) {
        expect(isSearchable(text), isTrue, reason: '"$text"');
      }
    });

    test('allows at most 100 characters after trimming', () {
      expect(isSearchable('a' * 100), isTrue);
      expect(isSearchable('  ${'a' * 100}  '), isTrue);
      expect(isSearchable('a' * 101), isFalse);
    });

    test('searchText removes the spaces around the text', () {
      expect(searchText('  švyturys \n'), 'švyturys');
    });

    test('the hint names the minimum', () {
      expect(searchHint, 'Įveskite bent 2 simbolius');
    });
  });

  group('Debouncer', () {
    const delay = Duration(milliseconds: 300);

    testWidgets('runs only the last call of a burst, after the delay',
        (tester) async {
      final debouncer = Debouncer(delay);
      final calls = <String>[];

      debouncer.run(() => calls.add('a'));
      await tester.pump(const Duration(milliseconds: 100));
      debouncer.run(() => calls.add('ab'));
      await tester.pump(const Duration(milliseconds: 100));
      debouncer.run(() => calls.add('abc'));

      await tester.pump(const Duration(milliseconds: 299));
      expect(calls, isEmpty); // not yet: 299 ms since the last call

      await tester.pump(const Duration(milliseconds: 2));
      expect(calls, ['abc']);
    });

    testWidgets('calls separated by more than the delay each run', (tester) async {
      final debouncer = Debouncer(delay);
      final calls = <String>[];

      debouncer.run(() => calls.add('first'));
      await tester.pump(delay);
      debouncer.run(() => calls.add('second'));
      await tester.pump(delay);

      expect(calls, ['first', 'second']);
    });

    testWidgets('cancel drops a pending call', (tester) async {
      final debouncer = Debouncer(delay);
      var called = false;

      debouncer.run(() => called = true);
      debouncer.cancel();
      await tester.pump(delay * 2);

      expect(called, isFalse);
    });
  });
}
