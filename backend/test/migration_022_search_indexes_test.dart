import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'migrations/022_global_catalog_courses_admin.sql',
    ).readAsStringSync();
  });

  test('migration 022 uses immutable scalar vectors and native array GIN', () {
    expect(migration, isNot(contains('array_to_string')));
    expect(
      migration,
      contains('idx_global_products_search ON global_products'),
    );
    expect(
      migration,
      contains('idx_global_products_search_keywords ON global_products'),
    );
    expect(migration, contains('idx_global_courses_search ON global_courses'));
    expect(
      migration,
      contains('idx_global_courses_search_keywords ON global_courses'),
    );
    expect(
      RegExp(r'USING GIN \(search_keywords\);').allMatches(migration),
      hasLength(2),
    );
  });

  test('migration 022 preserves casts, constraints, foreign keys and dedupe', () {
    expect(
      migration,
      contains('ALTER COLUMN user_id TYPE TEXT USING user_id::text'),
    );
    expect(
      migration,
      contains('ALTER COLUMN created_by TYPE TEXT USING created_by::text'),
    );
    expect(migration, contains("barcode ~ '^[0-9]{8,14}\$'"));
    expect(migration, contains("image_url ~ '^https://'"));
    expect(migration, contains("status IN ('pending','approved','rejected')"));
    expect(migration, contains('REFERENCES businesses(id) ON DELETE CASCADE'));
    expect(migration, contains('REFERENCES global_products(id)'));
    expect(migration, contains('REFERENCES global_courses(id)'));
    expect(
      migration,
      contains(
        'ON global_product_suggestions(business_id, barcode)\n  WHERE status = \'pending\'',
      ),
    );
  });
}
