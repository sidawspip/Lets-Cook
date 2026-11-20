import 'package:flutter_test/flutter_test.dart';
import 'package:lets_cook_mobile/services/browser_recovery.dart';

void main() {
  test('connection reset offers recovery without diagnosing the firewall', () {
    final message = browserFailureMessage('net::ERR_CONNECTION_RESET');
    expect(message, contains('site reset'));
    expect(message, contains('cached files'));
    expect(message, isNot(contains('firewall')));
  });
  test('certificate failure never suggests clearing security checks', () {
    final message = browserFailureMessage('net::ERR_CERT_AUTHORITY_INVALID');
    expect(message, contains('secure connection'));
    expect(message, isNot(contains('cached files')));
  });
  test('DNS and timeout failures have distinct recovery messages', () {
    expect(
      browserFailureMessage('net::ERR_NAME_NOT_RESOLVED'),
      contains('address'),
    );
    expect(browserFailureMessage('net::ERR_TIMED_OUT'), contains('too long'));
  });
}
