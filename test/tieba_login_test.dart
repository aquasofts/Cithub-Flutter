import 'package:cithub_flutter/features/tieba/tieba_login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the legacy mobile Tieba login endpoint and user agent', () {
    expect(
      tiebaMobileLoginUrl,
      'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine',
    );
    expect(tiebaMobileUserAgent, contains('Android 14'));
    expect(tiebaMobileUserAgent, contains('Mobile Safari/537.36'));
  });

  test('recognizes only supported HTTPS Tieba mobile Mine destinations', () {
    expect(
      isTiebaLoginCompletionUrl(
        'https://tieba.baidu.com/index/tbwise/mine?source=login',
      ),
      isTrue,
    );
    expect(
      isTiebaLoginCompletionUrl('https://tiebac.baidu.com/index/tbwise/mine'),
      isTrue,
    );
    expect(
      isTiebaLoginCompletionUrl('https://tieba.baidu.com/f?kw=test'),
      isFalse,
    );
    expect(
      isTiebaLoginCompletionUrl('http://tieba.baidu.com/index/tbwise/mine'),
      isFalse,
    );
    expect(
      isTiebaLoginCompletionUrl('https://attacker.test/index/tbwise/mine'),
      isFalse,
    );
  });
}
