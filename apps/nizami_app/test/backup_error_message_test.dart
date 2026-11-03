import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/backup/backup_page.dart';

final class _MinifiedLikeError {
  @override
  String toString() => "Instance of 'minified:rX'";
}

void main() {
  test('backup errors never expose minified Dart object names', () {
    expect(
      backupErrorMessage(
        _MinifiedLikeError(),
        fallback: 'تعذرت المزامنة الآن.',
      ),
      'تعذرت المزامنة الآن.',
    );
  });

  test('backup errors preserve an explicit server message', () {
    expect(
      backupErrorMessage(Exception('انتهت صلاحية الجلسة')),
      'انتهت صلاحية الجلسة',
    );
  });

  test('backup errors replace generic HTTP 5xx messages', () {
    expect(
      backupErrorMessage(
        Exception('Server Error'),
        fallback: 'تعذرت المزامنة الآن.',
      ),
      'تعذرت المزامنة الآن.',
    );
    expect(
      backupErrorMessage(
        StateError('HTTP 500'),
        fallback: 'تعذر إنشاء النسخة الاحتياطية.',
      ),
      'تعذر إنشاء النسخة الاحتياطية.',
    );
  });
}
