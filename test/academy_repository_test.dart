import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/repositories/academy_repository.dart';

void main() {
  test('AcademyRepository pode ser instanciado sem erros', () {
    final repository = AcademyRepository();
    expect(repository, isNotNull);
  });
}
