import '../../core/enums/origem_modalidade.dart';
import '../../core/enums/tipo_modalidade.dart';

/// Representa uma modalidade ativada e instalada por uma empresa específica.
/// Conecta a empresa a um template global, definindo sua hierarquia na conta.
class NegocioModalidade {
  /// Identificador único (UUID) da ativação.
  final String id;

  /// ID da empresa proprietária.
  final String businessId;

  /// Slug do template global referenciado (ex: 'salao_beleza').
  final String modalidadeSlug;

  /// Nível hierárquico da modalidade na empresa.
  final TipoModalidade tipo;

  /// Ordem de apresentação em interfaces visuais.
  final int ordemExibicao;

  /// Ícone customizado (se sobrescrito pela empresa).
  final String? icone;

  /// Cor customizada (se sobrescrito pela empresa).
  final String? cor;

  /// Se a modalidade está ativa para uso atual.
  final bool ativo;

  /// Se veio via instalação de template (importado) ou criada manualmente.
  final OrigemModalidade origem;

  /// Data de ativação/instalação.
  final DateTime createdAt;

  /// Data da última alteração.
  final DateTime updatedAt;

  /// Data de remoção (soft delete).
  final DateTime? deletedAt;

  /// Usuário que ativou a modalidade.
  final String? createdBy;

  /// Usuário que alterou por último.
  final String? updatedBy;

  const NegocioModalidade({
    required this.id,
    required this.businessId,
    required this.modalidadeSlug,
    required this.tipo,
    this.ordemExibicao = 0,
    this.icone,
    this.cor,
    this.ativo = true,
    this.origem = OrigemModalidade.importado,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.createdBy,
    this.updatedBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'modalidade_slug': modalidadeSlug,
      'tipo': tipo.nome,
      'ordem_exibicao': ordemExibicao,
      'icone': icone,
      'cor': cor,
      'ativo': ativo ? 1 : 0,
      'origem': origem.nome,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  factory NegocioModalidade.fromMap(Map<String, dynamic> map) {
    return NegocioModalidade(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      modalidadeSlug: map['modalidade_slug'] as String,
      tipo: TipoModalidadeExtension.fromNome(map['tipo'] as String),
      ordemExibicao: map['ordem_exibicao'] as int? ?? 0,
      icone: map['icone'] as String?,
      cor: map['cor'] as String?,
      ativo: (map['ativo'] as int? ?? 1) == 1,
      origem: OrigemModalidadeExtension.fromNome(
        map['origem'] as String? ?? 'importado',
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      createdBy: map['created_by'] as String?,
      updatedBy: map['updated_by'] as String?,
    );
  }
}
