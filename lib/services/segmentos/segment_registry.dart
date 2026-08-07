import '../../models/domain/segmento_template.dart';
import '../../repositories/segmento_templates_repository.dart';

/// Serviço de domínio responsável por gerenciar o catálogo global de Segmentos.
/// O Registry não possui nenhuma ligação com UI ou Widgets. Ele apenas expõe
/// e filtra os templates disponíveis para o sistema.
class SegmentRegistry {
  final SegmentoTemplatesRepository _templatesRepository;

  SegmentRegistry({SegmentoTemplatesRepository? templatesRepository})
    : _templatesRepository =
          templatesRepository ?? SegmentoTemplatesRepository();

  /// Retorna todos os templates de segmento disponíveis no catálogo do sistema.
  Future<List<SegmentoTemplate>> getAvailableTemplates() async {
    return await _templatesRepository.getAllActive();
  }

  /// Registra um novo template de segmento (por exemplo, via sincronização ou seed).
  Future<void> registerTemplate(SegmentoTemplate template) async {
    // Validações básicas de negócio podem ocorrer aqui
    if (template.slug.isEmpty || template.payloadConfigJson.isEmpty) {
      throw ArgumentError('O template precisa ter um slug e payload válidos.');
    }

    await _templatesRepository.save(template);
  }

  /// Busca um template específico pelo seu slug.
  Future<SegmentoTemplate?> getTemplate(String slug) async {
    return await _templatesRepository.getBySlug(slug);
  }
}
