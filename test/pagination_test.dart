import 'package:cithub_flutter/core/utils/pagination.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pagination append keeps the first item for each stable id', () {
    final items = <({String id, String value})>[(id: '1', value: 'page one')];

    appendUniqueBy(items, [
      (id: '1', value: 'duplicate'),
      (id: '2', value: 'page two'),
      (id: '2', value: 'duplicate in page'),
    ], (item) => item.id);

    expect(items, [(id: '1', value: 'page one'), (id: '2', value: 'page two')]);
  });

  test(
    'floor reply pages expose current, total pages, and total replies',
    () async {
      final page = await DemoCithubPlatform().loadFloorReplies(
        '1000',
        '10000002',
        page: 2,
      );

      expect(page.page, 2);
      expect(page.totalPages, 2);
      expect(page.totalReplies, 2);
      expect(page.replies, isNotEmpty);
    },
  );
}
