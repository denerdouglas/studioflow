import '../../core/enums/origem_modalidade.dart';
import '../../core/enums/tipo_modalidade.dart';
import '../../models/domain/negocio_modalidade.dart';
import '../../models/domain/segmento_template.dart';
import '../../repositories/negocio_modalidades_repository.dart';
import '../../core/utils/id_generator.dart';
import 'segment_registry.dart';

/// Exceção customizada para erros de instalação de segmentos.
class SegmentInstallationException implements Exception {
  final String message;
  SegmentInstallationException(this.message);
  @override
  String toString() => message;
}

/// Serviço de domínio responsável por instalar e gerenciar as modalidades
/// ativadas dentro de uma conta (business).
class SegmentInstaller {
  final NegocioModalidadesRepository _modalidadesRepository;
  final SegmentRegistry _registry;
  final IdGenerator _idGenerator;

  SegmentInstaller({
    NegocioModalidadesRepository? modalidadesRepository,
    SegmentRegistry? registry,
    IdGenerator? idGenerator,
  }) : _modalidadesRepository =
           modalidadesRepository ?? NegocioModalidadesRepository(),
       _registry = registry ?? SegmentRegistry(),
       _idGenerator = idGenerator ?? const UuidIdGenerator();

  /// Instala uma modalidade em um negócio a partir de um template global.
  Future<NegocioModalidade> install({
    required String businessId,
    required String modalidadeSlug,
    required TipoModalidade tipo,
    required String createdBy,
  }) async {
    final template = await _validateTemplate(modalidadeSlug);
    await _validateConstraints(businessId, tipo);

    return await _createAndSaveModality(
      businessId: businessId,
      template: template,
      tipo: tipo,
      createdBy: createdBy,
    );
  }

  /// Valida se o template existe e está ativo.
  Future<SegmentoTemplate> _validateTemplate(String slug) async {
    final template = await _registry.getTemplate(slug);
    if (template == null) {
      throw SegmentInstallationException(
        'Template de segmento não encontrado: \$slug',
      );
    }
    if (template.status != 'ativo') {
      throw SegmentInstallationException(
        'O template \$slug não está mais ativo.',
      );
    }
    return template;
  }

  /// Valida regras de negócio para a instalação, como a unicidade da principal.
  Future<void> _validateConstraints(
    String businessId,
    TipoModalidade tipo,
  ) async {
    if (tipo == TipoModalidade.principal) {
      final existingPrincipal = await _modalidadesRepository.getPrincipalActive(
        businessId,
      );
      if (existingPrincipal != null) {
        throw SegmentInstallationException(
          'A empresa já possui uma modalidade principal ativa. '
          'Apenas uma modalidade pode ser a base arquitetural da conta.',
        );
      }
    }
  }

  /// Cria o objeto de domínio e o persiste no repositório.
  Future<NegocioModalidade> _createAndSaveModality({
    required String businessId,
    required SegmentoTemplate template,
    required TipoModalidade tipo,
    required String createdBy,
  }) async {
    final now = DateTime.now().toUtc();
    final modalidade = NegocioModalidade(
      id: _idGenerator.generate(),
      businessId: businessId,
      modalidadeSlug: template.slug,
      tipo: tipo,
      ativo: true,
      origem: OrigemModalidade.importado,
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
    );

    await _modalidadesRepository.save(modalidade);

    // Futuro: Injetar o payload_config_json (serviços e categorias) no banco de dados.
    // Isso é feito decodificando template.payloadConfigJson e populando os catálogos.

    return modalidade;
  }
}
