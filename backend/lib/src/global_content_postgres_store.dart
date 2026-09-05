import 'package:postgres/postgres.dart';

import 'global_content.dart';

final class GlobalContentPostgresStore implements GlobalContentStore {
  final Pool pool;
  GlobalContentPostgresStore(this.pool);

  GlobalProduct _product(ResultRow row) {
    final value = row.toColumnMap();
    return GlobalProduct(
      id: value['id'] as String,
      barcode: value['barcode'] as String,
      brand: value['brand'] as String,
      name: value['name'] as String,
      variant: value['variant'] as String?,
      category: value['category'] as String,
      description: value['description'] as String?,
      imageUrl: value['image_url'] as String?,
      size: value['size'] as String?,
      active: value['active'] as bool,
      keywords: (value['search_keywords'] as List?)?.cast<String>() ?? const [],
      verified: value['verified'] as bool,
      createdBy: value['created_by'] as String,
      createdAt: value['created_at'] as DateTime,
      updatedAt: value['updated_at'] as DateTime,
    );
  }

  static const _productColumns = '''id,barcode,brand,name,variant,category,
    description,image_url,size,active,search_keywords,verified,created_by,
    created_at,updated_at''';

  @override
  Future<List<GlobalProduct>> listProducts() async => (await pool.execute(
    'SELECT $_productColumns FROM global_products ORDER BY updated_at DESC',
  )).map(_product).toList();

  @override
  Future<GlobalProduct?> productByBarcode(String barcode) async {
    final rows = await pool.execute(
      Sql.named(
        'SELECT $_productColumns FROM global_products WHERE barcode=@barcode AND active=true',
      ),
      parameters: {'barcode': barcode},
    );
    return rows.isEmpty ? null : _product(rows.first);
  }

  @override
  Future<GlobalProduct?> productById(String id) async {
    final rows = await pool.execute(
      Sql.named('SELECT $_productColumns FROM global_products WHERE id=@id'),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _product(rows.first);
  }

  @override
  Future<void> saveProduct(GlobalProduct item) async {
    await pool.execute(
      Sql.named('''INSERT INTO global_products ($_productColumns)
        VALUES(@id,@barcode,@brand,@name,@variant,@category,@description,
          @imageUrl,@size,@active,@keywords,@verified,@createdBy,@createdAt,@updatedAt)
        ON CONFLICT(id) DO UPDATE SET barcode=EXCLUDED.barcode,
          brand=EXCLUDED.brand,name=EXCLUDED.name,variant=EXCLUDED.variant,
          category=EXCLUDED.category,description=EXCLUDED.description,
          image_url=EXCLUDED.image_url,size=EXCLUDED.size,active=EXCLUDED.active,
          search_keywords=EXCLUDED.search_keywords,verified=EXCLUDED.verified,
          updated_at=EXCLUDED.updated_at'''),
      parameters: {
        'id': item.id,
        'barcode': item.barcode,
        'brand': item.brand,
        'name': item.name,
        'variant': item.variant,
        'category': item.category,
        'description': item.description,
        'imageUrl': item.imageUrl,
        'size': item.size,
        'active': item.active,
        'keywords': item.keywords,
        'verified': item.verified,
        'createdBy': item.createdBy,
        'createdAt': item.createdAt,
        'updatedAt': item.updatedAt,
      },
    );
  }

  ProductSuggestion _suggestion(ResultRow row) {
    final value = row.toColumnMap();
    return ProductSuggestion(
      id: value['id'] as String,
      barcode: value['barcode'] as String,
      businessId: value['business_id'] as String,
      name: value['name'] as String,
      brand: value['brand'] as String?,
      variant: value['variant'] as String?,
      category: value['category'] as String?,
      status: value['status'] as String,
      reviewedBy: value['reviewed_by'] as String?,
      reviewedAt: value['reviewed_at'] as DateTime?,
      createdAt: value['created_at'] as DateTime,
    );
  }

  static const _suggestionColumns =
      'id,barcode,business_id,name,brand,variant,category,status,reviewed_by,reviewed_at,created_at';

  @override
  Future<ProductSuggestion?> pendingSuggestion(
    String businessId,
    String barcode,
  ) async {
    final rows = await pool.execute(
      Sql.named(
        'SELECT $_suggestionColumns FROM global_product_suggestions WHERE business_id=@businessId AND barcode=@barcode AND status=\'pending\' LIMIT 1',
      ),
      parameters: {'businessId': businessId, 'barcode': barcode},
    );
    return rows.isEmpty ? null : _suggestion(rows.first);
  }

  @override
  Future<ProductSuggestion?> suggestionById(String id) async {
    final rows = await pool.execute(
      Sql.named(
        'SELECT $_suggestionColumns FROM global_product_suggestions WHERE id=@id',
      ),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _suggestion(rows.first);
  }

  @override
  Future<List<ProductSuggestion>> listSuggestions({String? status}) async {
    final rows = await pool.execute(
      Sql.named(
        'SELECT $_suggestionColumns FROM global_product_suggestions WHERE (@status::text IS NULL OR status=@status) ORDER BY created_at',
      ),
      parameters: {'status': status},
    );
    return rows.map(_suggestion).toList();
  }

  @override
  Future<void> saveSuggestion(ProductSuggestion item) async {
    await pool.execute(
      Sql.named('''INSERT INTO global_product_suggestions
        ($_suggestionColumns) VALUES(@id,@barcode,@businessId,@name,@brand,
          @variant,@category,@status,@reviewedBy,@reviewedAt,@createdAt)
        ON CONFLICT(id) DO UPDATE SET status=EXCLUDED.status,
          reviewed_by=EXCLUDED.reviewed_by,
          reviewed_at=EXCLUDED.reviewed_at'''),
      parameters: {
        'id': item.id,
        'barcode': item.barcode,
        'businessId': item.businessId,
        'name': item.name,
        'brand': item.brand,
        'variant': item.variant,
        'category': item.category,
        'status': item.status,
        'reviewedBy': item.reviewedBy,
        'reviewedAt': item.reviewedAt,
        'createdAt': item.createdAt,
      },
    );
  }

  GlobalCourse _course(ResultRow row) {
    final value = row.toColumnMap();
    return GlobalCourse(
      id: value['id'] as String,
      title: value['title'] as String,
      provider: value['provider'] as String,
      description: value['description'] as String,
      imageUrl: value['image_url'] as String?,
      category: value['category'] as String,
      keywords: (value['search_keywords'] as List?)?.cast<String>() ?? const [],
      active: value['active'] as bool,
      createdBy: value['created_by'] as String,
      createdAt: value['created_at'] as DateTime,
      updatedAt: value['updated_at'] as DateTime,
    );
  }

  static const _courseColumns =
      'id,title,provider,description,image_url,category,search_keywords,active,created_by,created_at,updated_at';

  @override
  Future<GlobalCourse?> courseById(String id) async {
    final rows = await pool.execute(
      Sql.named('SELECT $_courseColumns FROM global_courses WHERE id=@id'),
      parameters: {'id': id},
    );
    return rows.isEmpty ? null : _course(rows.first);
  }

  @override
  Future<List<GlobalCourse>> listCourses() async => (await pool.execute(
    'SELECT $_courseColumns FROM global_courses ORDER BY updated_at DESC',
  )).map(_course).toList();

  @override
  Future<List<GlobalCourse>> searchCourses(String query) async {
    final term = '%${query.trim()}%';
    final rows = await pool.execute(
      Sql.named(
        '''SELECT $_courseColumns FROM global_courses
        WHERE active=true AND (@empty OR title ILIKE @term OR provider ILIKE @term
          OR description ILIKE @term OR category ILIKE @term
          OR array_to_string(search_keywords,' ') ILIKE @term)
        ORDER BY CASE WHEN title ILIKE @term THEN 0 ELSE 1 END, updated_at DESC''',
      ),
      parameters: {'empty': query.trim().isEmpty, 'term': term},
    );
    return rows.map(_course).toList();
  }

  @override
  Future<void> saveCourse(GlobalCourse item) async {
    await pool.execute(
      Sql.named('''INSERT INTO global_courses ($_courseColumns)
        VALUES(@id,@title,@provider,@description,@imageUrl,@category,@keywords,
          @active,@createdBy,@createdAt,@updatedAt)
        ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,
          provider=EXCLUDED.provider,description=EXCLUDED.description,
          image_url=EXCLUDED.image_url,category=EXCLUDED.category,
          search_keywords=EXCLUDED.search_keywords,active=EXCLUDED.active,
          updated_at=EXCLUDED.updated_at'''),
      parameters: {
        'id': item.id,
        'title': item.title,
        'provider': item.provider,
        'description': item.description,
        'imageUrl': item.imageUrl,
        'category': item.category,
        'keywords': item.keywords,
        'active': item.active,
        'createdBy': item.createdBy,
        'createdAt': item.createdAt,
        'updatedAt': item.updatedAt,
      },
    );
  }
}
