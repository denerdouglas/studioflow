import 'dart:convert';

/// Representa a configuração global de uma empresa (business).
/// Isola a regra de negócio e formatação da entidade física do comércio.
class BusinessConfiguration {
  /// Identificador único da empresa.
  final String businessId;

  /// Idioma principal (ex: 'pt_BR').
  final String idioma;

  /// Idioma secundário para suporte multilíngue.
  final String? idiomaSecundario;

  /// Moeda padrão do sistema (ex: 'BRL').
  final String moeda;

  /// Formato de exibição de data (ex: 'dd/MM/yyyy').
  final String formatoData;

  /// Formato de exibição de hora (ex: 'HH:mm').
  final String formatoHora;

  /// Formato de exibição monetária (ex: 'R\$ #,##0.00').
  final String formatoMoeda;

  /// Fuso horário padrão da empresa (ex: 'America/Sao_Paulo').
  final String timezone;

  /// Dia que inicia a semana (0 = Domingo, 1 = Segunda).
  final int primeiroDiaSemana;

  /// Duração padrão sugerida para novos serviços (em minutos).
  final int duracaoPadrao;

  /// Estrutura flexível para regras de comissão da empresa.
  final Map<String, dynamic>? politicaComissao;

  /// País sede da empresa.
  final String? pais;

  /// Estado/Província da empresa.
  final String? estado;

  /// Cidade da empresa.
  final String? cidade;

  /// Preferências variadas armazenadas como JSON dinâmico.
  final Map<String, dynamic>? preferenciasJson;

  /// Data de criação do registro de configuração.
  final DateTime createdAt;

  /// Data da última atualização.
  final DateTime updatedAt;

  /// Data de deleção lógica.
  final DateTime? deletedAt;

  /// ID do usuário que criou o registro.
  final String? createdBy;

  /// ID do usuário que alterou o registro.
  final String? updatedBy;

  const BusinessConfiguration({
    required this.businessId,
    this.idioma = 'pt_BR',
    this.idiomaSecundario,
    this.moeda = 'BRL',
    this.formatoData = 'dd/MM/yyyy',
    this.formatoHora = 'HH:mm',
    this.formatoMoeda = r'R$ #,##0.00',
    this.timezone = 'America/Sao_Paulo',
    this.primeiroDiaSemana = 0,
    this.duracaoPadrao = 30,
    this.politicaComissao,
    this.pais,
    this.estado,
    this.cidade,
    this.preferenciasJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Converte a instância para um Map, tipicamente para ser salvo no banco SQLite.
  Map<String, dynamic> toMap() {
    return {
      'business_id': businessId,
      'idioma': idioma,
      'idioma_secundario': idiomaSecundario,
      'moeda': moeda,
      'formato_data': formatoData,
      'formato_hora': formatoHora,
      'formato_moeda': formatoMoeda,
      'timezone': timezone,
      'primeiro_dia_semana': primeiroDiaSemana,
      'duracao_padrao': duracaoPadrao,
      'politica_comissao': politicaComissao != null
          ? jsonEncode(politicaComissao)
          : null,
      'pais': pais,
      'estado': estado,
      'cidade': cidade,
      'preferencias_json': preferenciasJson != null
          ? jsonEncode(preferenciasJson)
          : null,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  /// Cria uma instância a partir de um Map retornado do banco ou API.
  factory BusinessConfiguration.fromMap(Map<String, dynamic> map) {
    return BusinessConfiguration(
      businessId: map['business_id'] as String,
      idioma: map['idioma'] as String? ?? 'pt_BR',
      idiomaSecundario: map['idioma_secundario'] as String?,
      moeda: map['moeda'] as String? ?? 'BRL',
      formatoData: map['formato_data'] as String? ?? 'dd/MM/yyyy',
      formatoHora: map['formato_hora'] as String? ?? 'HH:mm',
      formatoMoeda: map['formato_moeda'] as String? ?? r'R$ #,##0.00',
      timezone: map['timezone'] as String? ?? 'America/Sao_Paulo',
      primeiroDiaSemana: map['primeiro_dia_semana'] as int? ?? 0,
      duracaoPadrao: map['duracao_padrao'] as int? ?? 30,
      politicaComissao: map['politica_comissao'] != null
          ? jsonDecode(map['politica_comissao'] as String)
                as Map<String, dynamic>
          : null,
      pais: map['pais'] as String?,
      estado: map['estado'] as String?,
      cidade: map['cidade'] as String?,
      preferenciasJson: map['preferencias_json'] != null
          ? jsonDecode(map['preferencias_json'] as String)
                as Map<String, dynamic>
          : null,
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
