import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../models/domain/configuracao_comercio.dart';
import '../repositories/configuracoes_repository.dart';
import '../core/routes/app_routes.dart';
import 'app_bootstrap_page.dart';
import '../services/acesso_online_service.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';
import 'aparencia_page.dart';
import 'agendamento_online_page.dart';
import 'configuracao_comercial_page.dart';
import 'modelos_mensagens_page.dart';
import 'modalidades_page.dart';
import 'pagamentos_sprint4_page.dart';
import 'equipe_page.dart';
import 'minhas_unidades_page.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _repository = ConfiguracoesRepository();
  final _nome = TextEditingController();
  final _nomeExibicao = TextEditingController();
  final _telefone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _endereco = TextEditingController();
  final _pix = TextEditingController();
  final _abertura = TextEditingController();
  final _fechamento = TextEditingController();
  final _duracao = TextEditingController();
  Set<int> _dias = {};
  bool _notificacoes = true;
  bool _confirmarExclusoes = true;
  bool _carregando = true;
  bool _salvando = false;

  UsuarioAcesso get _usuario => SessionController.instance.usuario!;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final config = await _repository.carregar(_usuario.comercioId);
      _nome.text = config.nomeComercio;
      _nomeExibicao.text = config.nomeExibicao;
      _telefone.text = config.telefone;
      _whatsapp.text = config.whatsapp;
      _endereco.text = config.endereco;
      _pix.text = config.chavePix;
      _abertura.text = config.horarioAbertura;
      _fechamento.text = config.horarioFechamento;
      _duracao.text = config.duracaoPadraoMinutos.toString();
      _dias = {...config.diasFuncionamento};
      _notificacoes = config.notificacoesAtivas;
      _confirmarExclusoes = config.confirmarExclusoes;
    } catch (erro) {
      if (mounted) _mensagem('Não foi possível carregar as configurações.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().isEmpty ||
        _nomeExibicao.text.trim().isEmpty ||
        _telefone.text.trim().isEmpty ||
        _dias.isEmpty) {
      _mensagem('Preencha os campos obrigatórios e selecione ao menos um dia.');
      return;
    }
    final duracao = int.tryParse(_duracao.text);
    if (duracao == null || duracao < 5) {
      _mensagem('Informe uma duração padrão válida.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await _repository.salvar(
        ConfiguracaoComercio(
          comercioId: _usuario.comercioId,
          nomeComercio: _nome.text,
          nomeExibicao: _nomeExibicao.text,
          telefone: _telefone.text,
          whatsapp: _whatsapp.text,
          endereco: _endereco.text,
          chavePix: _pix.text,
          horarioAbertura: _abertura.text,
          horarioFechamento: _fechamento.text,
          diasFuncionamento: _dias,
          duracaoPadraoMinutos: duracao,
          notificacoesAtivas: _notificacoes,
          confirmarExclusoes: _confirmarExclusoes,
        ),
      );
      await SessionController.instance.atualizarUsuario();
      if (mounted) _mensagem('Configurações salvas.');
    } catch (erro) {
      if (mounted) _mensagem('Não foi possível salvar as configurações.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  void dispose() {
    for (final item in [
      _nome,
      _nomeExibicao,
      _telefone,
      _whatsapp,
      _endereco,
      _pix,
      _abertura,
      _fechamento,
      _duracao,
    ]) {
      item.dispose();
    }
    super.dispose();
  }

Future<void> _ativarServicos() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ativar Servios / Salo?'),
        content: const Text('Isso adicionar os mdulos de Agenda, Servios e Profissionais ao seu menu. Os dados de Loja no sero afetados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _carregando = true);
    try {
      final db = await DatabaseService.instance.database;
      await db.update('comercios', {'modulo_servicos_ativo': 1}, where: 'id = ?', whereArgs: [_usuario.comercioId]);

      final api = AcessoOnlineService();
      if (api.configurado) {
        await api.updateModules(comercioId: _usuario.comercioId, moduloLojaAtivo: _usuario.moduloLojaAtivo, moduloServicosAtivo: true);
      }

      await SessionController.instance.inicializar();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        AppRoutes.material(builder: (_) => const AppBootstrapPage()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao ativar: ')));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exibeServicos = _usuario.moduloServicosAtivo;
    if (!_usuario.pode(ModuloPermissao.configuracoes)) {
      return const Scaffold(
        body: Center(child: Text('Acesso às configurações não permitido.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Configurações')),
      body: _carregando
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (exibeServicos)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.groups_outlined),
                      title: Text('Equipe'),
                    subtitle: Text('Ativos, solicitações e inativos'),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(builder: (_) => const EquipePage()),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.swap_horiz),
                    title: Text('Minhas unidades'),
                    subtitle: Text('Trocar de unidade com segurança'),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(
                        builder: (_) => const MinhasUnidadesPage(),
                      ),
                    ),
                  ),
                ),
                _titulo('Comércio'),
                _campo(_nome, 'Nome do comércio *', Icons.storefront),
                _campo(_nomeExibicao, 'Nome exibido *', Icons.badge),
                _campo(
                  _telefone,
                  'Telefone *',
                  Icons.phone,
                  teclado: TextInputType.phone,
                ),
                _campo(
                  _whatsapp,
                  'WhatsApp',
                  Icons.chat_outlined,
                  teclado: TextInputType.phone,
                ),
                _campo(_endereco, 'Endereço', Icons.location_on_outlined),
                _campo(_pix, 'Chave Pix', Icons.pix),
                SizedBox(height: 4),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.location_on_outlined),
                    title: Text('Endereço e localização'),
                    subtitle: Text(
                      'Endereço completo, rota e compartilhamento',
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(
                        builder: (_) => const ConfiguracaoComercialPage(),
                      ),
                    ),
                  ),
                ),
                if (_usuario.pode(ModuloPermissao.financeiro) &&
                    _usuario.podeAcao(AcaoPermissao.configurarPix))
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.pix),
                      title: Text('Pagamentos e Pix'),
                      subtitle: Text(
                        'Chave, recebedor, sinal e formas aceitas',
                      ),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        AppRoutes.material(
                          builder: (_) => const PagamentosSprint4Page(),
                        ),
                      ),
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.category_outlined),
                    title: Text('Modalidades'),
                    subtitle: Text(
                      'Áreas do estabelecimento, vínculos e atalhos da Home',
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(
                        builder: (_) => const ModalidadesPage(),
                      ),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.event_available_outlined),
                    title: Text('Agendamento Online'),
                    subtitle: Text('Link público, compartilhamento e QR Code'),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(
                        builder: (_) => const AgendamentoOnlinePage(),
                      ),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.palette_outlined),
                    title: Text('Aparência'),
                    subtitle: Text('Logo, cores e tema claro ou escuro'),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(builder: (_) => const AparenciaPage()),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.message_outlined),
                    title: Text('Modelos de mensagens'),
                    subtitle: Text(
                      'Editar, testar, duplicar e restaurar modelos',
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(
                        builder: (_) => const ModelosMensagensPage(),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                _titulo('Funcionamento'),
                Row(
                  children: [
                    Expanded(
                      child: _campo(_abertura, 'Abertura', Icons.schedule),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _campo(_fechamento, 'Fechamento', Icons.schedule),
                    ),
                  ],
                ),
                _campo(
                  _duracao,
                  'Duração padrão (minutos)',
                  Icons.timer_outlined,
                  teclado: TextInputType.number,
                ),
                Text('Dias de funcionamento'),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (indice) {
                    final dia = indice + 1;
                    const nomes = [
                      'Seg',
                      'Ter',
                      'Qua',
                      'Qui',
                      'Sex',
                      'Sáb',
                      'Dom',
                    ];
                    return FilterChip(
                      label: Text(nomes[indice]),
                      selected: _dias.contains(dia),
                      onSelected: (valor) {
                        setState(() {
                          if (valor) {
                            _dias.add(dia);
                          } else {
                            _dias.remove(dia);
                          }
                        });
                      },
                    );
                  }),
                ),
                SizedBox(height: 16),
                _titulo('Preferências'),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.attach_money),
                  title: Text('Moeda'),
                  subtitle: Text('Real brasileiro (BRL)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _notificacoes,
                  title: Text('Notificações ativadas'),
                  onChanged: (valor) => setState(() => _notificacoes = valor),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmarExclusoes,
                  title: Text('Confirmar antes de excluir registros'),
                  onChanged: (valor) =>
                      setState(() => _confirmarExclusoes = valor),
                ),
                SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: Icon(Icons.save_outlined),
                  label: Text(
                    _salvando ? 'Salvando...' : 'Salvar configurações',
                  ),
                ),

                if (!exibeServicos) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _ativarServicos,
                    icon: const Icon(Icons.store),
                    label: const Text('Ativar Servios / Salo'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        texto,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _campo(
    TextEditingController controller,
    String label,
    IconData icone, {
    TextInputType? teclado,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: teclado,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icone)),
      ),
    );
  }
}
