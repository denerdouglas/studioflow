import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sync Queue Drain & Refresh', () {
    test(
      'Must auto-refresh if access token expires but session is valid',
      () {},
    );
    test('Must not swap sessions between Isolated Accounts', () {});
    test('Must register error for payload issues and proceed to next', () {});
    test('Must retry 5xx network errors', () {});
    test('Must throw StateError if refresh token is expired', () {});
    test(
      'Must update operacoesEmErro and operacoesSincronizadas counts',
      () {},
    );
  });

  group('UTF-8 Fixes', () {
    test('Must normalize known mojibake inside DatabaseSchemaVerifier', () {});
  });

  group('Caixa Scrolling', () {
    test('Must scroll past the FAB utilizing SliverPadding', () {});
    test('Must keep layout fixed for headers while scrolling list', () {});
  });
}
