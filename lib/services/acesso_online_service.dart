import '../models/domain/acesso.dart';
import '../models/domain/sincronizacao_backend.dart';
import '../repositories/acesso_repository.dart';
import 'backend_api_client.dart';
import 'backend_token_vault.dart';

class ResultadoAcessoOnline {
  final UsuarioAcesso? usuario;
  final List<Map<String, dynamic>> contas;

  const ResultadoAcessoOnline({this.usuario, this.contas = const []});
  bool get exigeSelecao => usuario == null && contas.isNotEmpty;
}

class AcessoOnlineService {
  static const endpointCompilado = String.fromEnvironment(
    'STUDIOFLOW_PUBLIC_BACKEND_URL',
    defaultValue: 'https://api.studioflowapp.com.br',
  );

  final BackendApiClient _api;
  final BackendTokenVault _vault;
  final AcessoRepository _repository;
  final String endpoint;

  AcessoOnlineService({
    BackendApiClient? api,
    BackendTokenVault? vault,
    AcessoRepository? repository,
    String? endpoint,
  }) : _api = api ?? BackendApiClient(),
       _vault = vault ?? const SecureBackendTokenVault(),
       _repository = repository ?? AcessoRepository(),
       endpoint = endpoint ?? endpointCompilado;

  bool get configurado => endpoint.trim().isNotEmpty;

  Future<ResultadoAcessoOnline> entrar({
    required String login,
    required String senha,
    String? comercioId,
  }) async {
    if (!configurado) {
      throw StateError('Backend principal não configurado neste aplicativo.');
    }
    final uri = _api.normalizeEndpoint(endpoint);
    final response = await _api.login(
      endpoint: uri,
      login: login,
      password: senha,
      businessId: comercioId,
    );
    if (response['selectionRequired'] == true) {
      final raw = response['accounts'] as List? ?? const [];
      return ResultadoAcessoOnline(
        contas: raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
    }
    final account = Map<String, dynamic>.from(response['account'] as Map);
    final usuario = await _repository.restaurarContaOnline(
      account: account,
      senhaValidada: senha,
      endpoint: uri.toString(),
    );
    await _vault.write(
      SessaoBackend(
        comercioId: account['businessId'] as String,
        usuarioId: account['userId'] as String,
        accessToken: response['accessToken'] as String,
        refreshToken: response['refreshToken'] as String,
        refreshExpiraEm: DateTime.parse(
          response['refreshTokenExpiresAt'] as String,
        ),
      ),
    );
    return ResultadoAcessoOnline(usuario: usuario);
  }

  Future<UsuarioAcesso> cadastrar({
    required CadastroComercioEntrada entrada,
    required String comercioId,
    required String usuarioId,
  }) async {
    if (!configurado) {
      throw StateError('Backend principal não configurado neste aplicativo.');
    }
    final uri = _api.normalizeEndpoint(endpoint);
    final response = await _api.registerBusiness(
      endpoint: uri,
      businessId: comercioId,
      businessName: entrada.nomeComercio,
      segment: entrada.tipoEstabelecimento.name,
      userId: usuarioId,
      ownerName: entrada.responsavel,
      phone: entrada.telefone,
      login: entrada.email,
      password: entrada.senha,
    );
    final account = Map<String, dynamic>.from(response['account'] as Map);
    final usuario = await _repository.restaurarContaOnline(
      account: account,
      senhaValidada: entrada.senha,
      endpoint: uri.toString(),
    );
    await _vault.write(
      SessaoBackend(
        comercioId: account['businessId'] as String,
        usuarioId: account['userId'] as String,
        accessToken: response['accessToken'] as String,
        refreshToken: response['refreshToken'] as String,
        refreshExpiraEm: DateTime.parse(
          response['refreshTokenExpiresAt'] as String,
        ),
      ),
    );
    return usuario;
  }
}
