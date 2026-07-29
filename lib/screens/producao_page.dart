import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../models/domain/infraestrutura.dart';
import '../models/domain/sincronizacao_backend.dart';
import '../repositories/infraestrutura_repository.dart';
import '../services/backend_sync_service.dart';
import '../services/session_controller.dart';

class ProducaoPage extends StatefulWidget {
  const ProducaoPage({super.key});

  @override
  State<ProducaoPage> createState() => _ProducaoPageState();
}

class _ProducaoPageState extends State<ProducaoPage> {
  final _repository = InfraestruturaRepository();
  final _syncService = BackendSyncService();
  late Future<EstadoInfraestrutura> _estado;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _estado = _repository.carregarEstado();
  }

  void _recarregar() => setState(() => _estado = _repository.carregarEstado());

  void _explicarDependencia() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend ainda não configurado'),
        content: const Text(
          'O StudioFlow continua funcionando localmente. Sincronização, assinaturas e painel web exigem um backend seguro e credenciais fornecidas fora do aplicativo. Nenhuma chave foi gravada no APK.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _conectar(
    UsuarioAcesso usuario,
    EstadoInfraestrutura estado,
  ) async {
    final endpoint = TextEditingController(text: estado.endpointPublico ?? '');
    final login = TextEditingController(text: usuario.emailLogin);
    final senha = TextEditingController();
    var criarAmbiente = false;
    final input = await showDialog<_BackendInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Conectar ao StudioFlow Cloud'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Use somente o endereço HTTPS fornecido pela ROLG Systems. '
                  'A senha é enviada por conexão segura e não fica salva.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: endpoint,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint HTTPS',
                    hintText: 'https://api.studioflow.com.br',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: login,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Login online'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: senha,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha online'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: criarAmbiente,
                  onChanged: (value) =>
                      setDialogState(() => criarAmbiente = value ?? false),
                  title: const Text(
                    'Criar ambiente remoto se ainda não existir',
                  ),
                  subtitle: const Text(
                    'Disponível somente para o dono no primeiro vínculo.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _BackendInput(
                  endpoint: endpoint.text,
                  login: login.text,
                  senha: senha.text,
                  criarAmbiente: criarAmbiente,
                ),
              ),
              child: const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
    endpoint.dispose();
    login.dispose();
    senha.dispose();
    if (input == null) return;
    if (input.criarAmbiente && usuario.funcao != FuncaoUsuario.dono) {
      _mensagem('Somente o dono pode criar o ambiente remoto.');
      return;
    }
    await _executar(() async {
      await _syncService.conectar(
        usuario: usuario,
        credenciais: CredenciaisBackend(
          endpoint: input.endpoint,
          login: input.login,
          senha: input.senha,
        ),
        criarAmbienteSeAusente: input.criarAmbiente,
      );
      final resultado = await _syncService.sincronizar(usuario.comercioId);
      _mensagem(
        'Conectado: ${resultado.enviadas} enviados e '
        '${resultado.recebidas} recebidos.',
      );
    });
  }

  Future<void> _sincronizar(String comercioId) async {
    await _executar(() async {
      final resultado = await _syncService.sincronizar(comercioId);
      _mensagem(
        '${resultado.enviadas} enviados, ${resultado.recebidas} recebidos, '
        '${resultado.conflitos} conflitos.',
      );
    });
  }

  Future<void> _desconectar(String comercioId) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar sincronização?'),
        content: const Text(
          'Os dados locais serão preservados. Será necessário entrar novamente '
          'para voltar a sincronizar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    await _executar(() => _syncService.desconectar(comercioId));
  }

  Future<void> _executar(Future<void> Function() action) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await action();
    } on Object catch (error) {
      _mensagem(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _estado = _repository.carregarEstado();
        });
      }
    }
  }

  void _mensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SessionController.instance.usuario!;
    if (!usuario.pode(ModuloPermissao.configuracoes)) {
      return const Scaffold(
        body: Center(child: Text('Acesso não autorizado.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Produção e sincronização')),
      body: FutureBuilder<EstadoInfraestrutura>(
        future: _estado,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Não foi possível carregar: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _recarregar,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          final estado = snapshot.requireData;
          return RefreshIndicator(
            onRefresh: () async => _recarregar(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(
                  icon: Icons.offline_bolt_outlined,
                  title: 'Operação local',
                  detail:
                      'Disponível — dados persistidos no SQLite por comércio.',
                  ok: true,
                ),
                _StatusCard(
                  icon: Icons.store_mall_directory_outlined,
                  title: 'Multiunidades',
                  detail:
                      '${estado.unidadePrincipal.nome} (${estado.unidadePrincipal.codigo}) criada como unidade principal.',
                  ok: true,
                ),
                _StatusCard(
                  icon: Icons.sync_outlined,
                  title: 'Fila de sincronização',
                  detail:
                      '${estado.operacoesPendentes} operação(ões) pendente(s). '
                      '${estado.backendConfigurado ? 'Envio online ativo.' : 'Envio online desativado.'}',
                  ok: estado.operacoesPendentes == 0,
                ),
                _StatusCard(
                  icon: Icons.cloud_off_outlined,
                  title: 'Backend / Firebase',
                  detail: estado.backendConfigurado
                      ? 'Provedor ${estado.provedorBackend} configurado. '
                            'Cursor ${estado.ultimoCursor}. '
                            '${estado.ultimaSincronizacao == null ? 'Aguardando primeira sincronização.' : 'Última sincronização: ${estado.ultimaSincronizacao}.'}'
                      : 'Não configurado — requer endpoint e credenciais seguras.',
                  ok: estado.backendConfigurado,
                ),
                const _StatusCard(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Assinaturas e painel administrativo',
                  detail:
                      'Contratos preparados; serviço externo ainda não conectado.',
                  ok: false,
                ),
                const _StatusCard(
                  icon: Icons.storefront_outlined,
                  title: 'Marketplace StudioFlow',
                  detail:
                      'Arquitetura separada; nenhuma integração foi simulada como real.',
                  ok: false,
                ),
                const SizedBox(height: 12),
                if (_ocupado)
                  const Center(child: CircularProgressIndicator())
                else if (!estado.backendConfigurado)
                  FilledButton.icon(
                    onPressed: () => _conectar(usuario, estado),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Conectar ao StudioFlow Cloud'),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: () => _sincronizar(usuario.comercioId),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar agora'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _desconectar(usuario.comercioId),
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: const Text('Desconectar nuvem'),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _explicarDependencia,
                  child: const Text('Ver dependências externas'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool ok;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green.shade700 : Colors.orange.shade800;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(detail),
        trailing: Icon(ok ? Icons.check_circle : Icons.info, color: color),
      ),
    );
  }
}

class _BackendInput {
  final String endpoint;
  final String login;
  final String senha;
  final bool criarAmbiente;

  const _BackendInput({
    required this.endpoint,
    required this.login,
    required this.senha,
    required this.criarAmbiente,
  });
}
