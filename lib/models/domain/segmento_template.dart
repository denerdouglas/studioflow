import 'dart:convert';

/// Representa o template-base de um segmento que será instalado em uma conta.
/// Este template pertence ao sistema (catálogo global) e define a estrutura do segmento.
class SegmentoTemplate {
  /// Slug identificador único e legível (ex: 'salao_beleza', 'barbearia_padrao').
  final String slug;

  /// Nome de exibição amigável do segmento.
  final String nome;

  /// Grupo/Categoria maior a qual o segmento pertence (ex: 'Beleza', 'Saúde').
  final String grupo;

  /// Payload estruturado contendo a árvore de serviços, permissões e dashboards padrões.
  final Map<String, dynamic> payloadConfigJson;

  /// Versão iterativa do template.
  final int versao;

  /// Checksum de integridade para garantir que o payload não foi adulterado localmente.
  final String? checksum;

  /// Status do template no sistema ('ativo', 'obsoleto', 'manutencao').
  final String status;

  /// Origem do template ('sistema', 'parceiro').
  final String origem;

  /// Data de criação no catálogo.
  final DateTime createdAt;

  /// Data da última alteração no catálogo.
  final DateTime updatedAt;

  /// Data de exclusão lógica (soft delete).
  final DateTime? deletedAt;

  const SegmentoTemplate({
    required this.slug,
    required this.nome,
    required this.grupo,
    required this.payloadConfigJson,
    this.versao = 1,
    this.checksum,
    this.status = 'ativo',
    this.origem = 'sistema',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'slug': slug,
      'nome': nome,
      'grupo': grupo,
      'payload_config_json': jsonEncode(payloadConfigJson),
      'versao': versao,
      'checksum': checksum,
      'status': status,
      'origem': origem,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory SegmentoTemplate.fromMap(Map<String, dynamic> map) {
    return SegmentoTemplate(
      slug: map['slug'] as String,
      nome: map['nome'] as String,
      grupo: map['grupo'] as String,
      payloadConfigJson:
          jsonDecode(map['payload_config_json'] as String)
              as Map<String, dynamic>,
      versao: map['versao'] as int? ?? 1,
      checksum: map['checksum'] as String?,
      status: map['status'] as String? ?? 'ativo',
      origem: map['origem'] as String? ?? 'sistema',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }
}
