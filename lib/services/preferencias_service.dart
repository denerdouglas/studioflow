import 'package:shared_preferences/shared_preferences.dart';

class PreferenciasService {
  PreferenciasService._();

  static final SharedPreferencesAsync _preferencias = SharedPreferencesAsync();

  static const String _chaveCadastroConcluido = 'cadastro_concluido';
  static const String _chaveNomeResponsavel = 'nome_responsavel';
  static const String _chaveNomeNegocio = 'nome_negocio';
  static const String _chaveTipoNegocio = 'tipo_negocio';
  static const String _chaveTema = 'tema_negocio';

  static Future<void> salvarCadastro({
    required String nomeResponsavel,
    required String nomeNegocio,
    required String tipoNegocio,
    required String tema,
  }) async {
    await _preferencias.setString(_chaveNomeResponsavel, nomeResponsavel);

    await _preferencias.setString(_chaveNomeNegocio, nomeNegocio);

    await _preferencias.setString(_chaveTipoNegocio, tipoNegocio);

    await _preferencias.setString(_chaveTema, tema);

    await _preferencias.setBool(_chaveCadastroConcluido, true);
  }

  static Future<bool> cadastroConcluido() async {
    return await _preferencias.getBool(_chaveCadastroConcluido) ?? false;
  }

  static Future<Map<String, String>> carregarCadastro() async {
    final String nomeResponsavel =
        await _preferencias.getString(_chaveNomeResponsavel) ?? '';

    final String nomeNegocio =
        await _preferencias.getString(_chaveNomeNegocio) ?? '';

    final String tipoNegocio =
        await _preferencias.getString(_chaveTipoNegocio) ?? '';

    final String tema = await _preferencias.getString(_chaveTema) ?? 'elegante';

    return {
      'nomeResponsavel': nomeResponsavel,
      'nomeNegocio': nomeNegocio,
      'tipoNegocio': tipoNegocio,
      'tema': tema,
    };
  }

  static Future<void> apagarCadastro() async {
    await _preferencias.remove(_chaveCadastroConcluido);

    await _preferencias.remove(_chaveNomeResponsavel);

    await _preferencias.remove(_chaveNomeNegocio);

    await _preferencias.remove(_chaveTipoNegocio);

    await _preferencias.remove(_chaveTema);
  }
}
