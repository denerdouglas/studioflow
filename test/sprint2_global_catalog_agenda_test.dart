import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:studioflow/models/domain/commercial_campaign.dart';
import 'package:studioflow/models/domain/global_course.dart';
import 'package:studioflow/screens/novo_agendamento_sheet.dart';
import 'package:studioflow/services/preferencias_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curso preserva campanha afiliada, identificação e link remoto', () {
    final course = GlobalCourse.fromJson({
      'id': 'solda',
      'title': 'Curso de Solda Profissional',
      'provider': 'Parceiro',
      'description': 'Solda MIG e TIG',
      'category': 'Solda',
      'keywords': ['soldador', 'mig', 'tig'],
      'campaign': {
        'id': 'offer',
        'title': 'Oferta',
        'destinationUrl': 'https://parceiro.test/solda',
        'sourceType': 'affiliate',
        'ctaText': 'Ver curso',
        'priority': 10,
        'courseId': 'solda',
      },
    });

    expect(course.campaign?.disclosure, 'Publicidade');
    expect(course.campaign?.courseId, 'solda');
    expect(
      CommercialCampaign.safeDestination(course.campaign!.destinationUrl)?.host,
      'parceiro.test',
    );
  });

  test(
    'preferência de horários livres é opt-in e isolada por negócio',
    () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      expect(
        await PreferenciasService.mostrarHorariosLivres('business-a'),
        isFalse,
      );
      await PreferenciasService.salvarMostrarHorariosLivres('business-a', true);
      expect(
        await PreferenciasService.mostrarHorariosLivres('business-a'),
        isTrue,
      );
      expect(
        await PreferenciasService.mostrarHorariosLivres('business-b'),
        isFalse,
      );
    },
  );

  test('novo agendamento aceita horário e profissional pré-selecionados', () {
    final horario = DateTime(2026, 9, 5, 14, 30);
    final sheet = NovoAgendamentoSheet(
      dataBase: horario,
      profissionais: const [],
      horarioInicial: horario,
      profissionalInicialId: 'professional-1',
    );
    expect(sheet.horarioInicial, horario);
    expect(sheet.profissionalInicialId, 'professional-1');
  });
}
