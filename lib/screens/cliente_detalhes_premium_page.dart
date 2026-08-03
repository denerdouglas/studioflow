import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../core/helpers/app_formatters.dart';
import '../models/domain/atendimento.dart';
import '../models/domain/cliente.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/cliente_fotos_repository.dart';
import '../repositories/cliente_360_repository.dart';
import '../services/session_controller.dart';
import '../widgets/shared/premium_card.dart';
import '../widgets/shared/simple_bar_chart.dart';
import 'agenda_page.dart';
import 'anamnese_page.dart';
import 'clientes_360_page.dart';

class ClienteDetalhesPremiumPage extends StatefulWidget {
  final ClienteRegistro cliente;
  final ClienteRepository repository;

  const ClienteDetalhesPremiumPage({
    super.key,
    required this.cliente,
    required this.repository,
  });

  @override
  State<ClienteDetalhesPremiumPage> createState() =>
      _ClienteDetalhesPremiumPageState();
}

class _ClienteDetalhesPremiumPageState extends State<ClienteDetalhesPremiumPage>
    with SingleTickerProviderStateMixin {
  late ClienteRegistro _cliente;
  late TabController _tabController;
  final _fotosRepository = ClienteFotosRepository();
  final _cliente360Repository = Cliente360Repository();

  bool _carregando = true;
  ResumoCliente360? _resumo360;
  List<FotoCliente> _fotos = [];

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    _tabController = TabController(length: 5, vsync: this);
    _carregarDados();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final resultados = await Future.wait([
        _cliente360Repository.carregar(_cliente.id),
        _fotosRepository.listarPorCliente(_cliente.id),
      ]);
      if (!mounted) return;
      setState(() {
        _resumo360 = resultados[0] as ResumoCliente360;
        _fotos = resultados[1] as List<FotoCliente>;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  Future<void> _alterarFoto() async {
    final opcao = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Foto da cliente'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.camera_alt_outlined),
                  SizedBox(width: 12),
                  Text('Tirar foto'),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'galeria'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined),
                  SizedBox(width: 12),
                  Text('Escolher da galeria'),
                ],
              ),
            ),
          ),
          if (_cliente.avatarPathLocal != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'remover'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Remover foto', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (opcao == null) return;

    if (opcao == 'remover') {
      _atualizarAvatar(null);
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: opcao == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 70,
    );

    if (image == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final comercioId = SessionController.instance.usuario!.comercioId;
    final dirPath = path.join(appDir.path, comercioId, 'clientes');
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final fileName =
        '${_cliente.id}_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = path.join(dirPath, fileName);
    await File(image.path).copy(savedPath);

    _atualizarAvatar(savedPath);
  }

  Future<void> _atualizarAvatar(String? novoPath) async {
    final clienteAtualizado = _cliente.copiarCom(avatarPathLocal: novoPath);
    try {
      await widget.repository.atualizar(clienteAtualizado);
      if (!mounted) return;
      setState(() => _cliente = clienteAtualizado);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao atualizar foto.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final corPrincipal = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 320,
              pinned: true,
              backgroundColor: _cliente.avatarPathLocal != null
                  ? Colors.black
                  : corPrincipal,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  _cliente.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cliente.avatarPathLocal != null)
                      Image.file(
                        File(_cliente.avatarPathLocal!),
                        fit: BoxFit.cover,
                      )
                    else
                      Container(
                        color: corPrincipal,
                        child: Center(
                          child: Text(
                            _iniciais(_cliente.nome),
                            style: const TextStyle(
                              fontSize: 60,
                              color: Colors.white54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black38,
                            Colors.transparent,
                            Colors.black87,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 70,
                      child: FloatingActionButton.small(
                        heroTag: null,
                        onPressed: _alterarFoto,
                        backgroundColor: Colors.white,
                        foregroundColor: corPrincipal,
                        child: const Icon(Icons.camera_alt),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  tooltip: 'Agendar',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgendaPage(clienteInicial: _cliente),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.assignment),
                  tooltip: 'Ficha de Anamnese',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnamnesePage(
                        clienteId: _cliente.id,
                        nomeCliente: _cliente.nome,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.threed_rotation),
                  tooltip: 'Visão 360',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          Cliente360DetalhePage(clienteId: _cliente.id),
                    ),
                  ),
                ),
              ],
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: corPrincipal,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: corPrincipal,
                  tabs: const [
                    Tab(text: 'Resumo'),
                    Tab(text: 'Histórico'),
                    Tab(text: 'Fotos'),
                    Tab(text: 'Produtos'),
                    Tab(text: 'Anotações'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _ResumoTab(cliente: _cliente, resumo: _resumo360),
                  _HistoricoTab(historico: _resumo360?.historicoAgenda ?? []),
                  _FotosTab(fotos: _fotos, onAdicionar: _adicionarFoto),
                  _ProdutosTab(compras: _resumo360?.historicoCompras ?? []),
                  _AnotacoesTab(
                    cliente: _cliente,
                    repository: widget.repository,
                    onAtualizado: (c) => setState(() => _cliente = c),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _adicionarFoto() async {
    final opcao = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Adicionar foto'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.camera_alt_outlined),
                  SizedBox(width: 12),
                  Text('Tirar foto'),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'galeria'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined),
                  SizedBox(width: 12),
                  Text('Escolher da galeria'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (opcao == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: opcao == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 70,
    );

    if (image == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final comercioId = SessionController.instance.usuario!.comercioId;
    final dirPath = path.join(
      appDir.path,
      comercioId,
      'clientes',
      _cliente.id,
      'fotos',
    );
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final fileId = DateTime.now().millisecondsSinceEpoch.toString();
    final savedPath = path.join(dirPath, '$fileId.jpg');
    await File(image.path).copy(savedPath);

    final novaFoto = FotoCliente(
      id: fileId,
      comercioId: comercioId,
      clienteId: _cliente.id,
      filePathLocal: savedPath,
      thumbnailPath: savedPath,
      categoria: 'Geral',
      dataTrabalho: DateTime.now(),
      criadoEm: DateTime.now().toUtc(),
      atualizadoEm: DateTime.now().toUtc(),
    );

    try {
      await _fotosRepository.inserir(novaFoto);
      if (!mounted) return;
      setState(() {
        _fotos.insert(0, novaFoto);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Foto adicionada.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao salvar foto.')));
    }
  }

  String _iniciais(String nome) {
    final partes = nome.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _ResumoTab extends StatelessWidget {
  final ClienteRegistro cliente;
  final ResumoCliente360? resumo;

  const _ResumoTab({required this.cliente, this.resumo});

  @override
  Widget build(BuildContext context) {
    List<BarChartData> chartData = [];
    if (resumo != null) {
      // Create chart data for the last 6 months
      final now = DateTime.now();
      final Map<String, int> counts = {};
      for (int i = 5; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        final monthStr =
            '${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
        counts[monthStr] = 0;
      }
      for (var a in resumo!.historicoAgenda) {
        if (a['status'] == 'concluido' || a['status'] == 'agendado') {
          final dt = DateTime.parse(a['inicio'] as String);
          final monthStr =
              '${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';
          if (counts.containsKey(monthStr)) {
            counts[monthStr] = counts[monthStr]! + 1;
          }
        }
      }
      chartData = counts.entries
          .map((e) => BarChartData(e.key, e.value.toDouble()))
          .toList();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _AcaoRapida(icone: Icons.chat, label: 'WhatsApp', onTap: () {}),
            _AcaoRapida(icone: Icons.phone, label: 'Ligar', onTap: () {}),
            _AcaoRapida(
              icone: Icons.camera_alt,
              label: 'Instagram',
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 24),
        PremiumCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('Telefone / WhatsApp'),
                subtitle: Text(cliente.whatsapp),
              ),
              if (cliente.email.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('E-mail'),
                  subtitle: Text(cliente.email),
                ),
              ListTile(
                leading: const Icon(Icons.cake),
                title: const Text('Aniversário'),
                subtitle: Text(
                  cliente.dataNascimento != null
                      ? '${cliente.dataNascimento!.day}/${cliente.dataNascimento!.month}'
                      : 'Não informado',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (resumo != null)
          PremiumCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Métricas',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Metrica(
                        valor: '${resumo!.agendamentos}',
                        label: 'Agendamentos',
                      ),
                      _Metrica(valor: '${resumo!.faltas}', label: 'Faltas'),
                      _Metrica(
                        valor: AppFormatters.moeda(resumo!.comprasProdutos),
                        label: 'Produtos',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (resumo != null && chartData.isNotEmpty)
          PremiumCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Frequência (Últimos 6 meses)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  SimpleBarChart(data: chartData),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AcaoRapida extends StatelessWidget {
  final IconData icone;
  final String label;
  final VoidCallback onTap;

  const _AcaoRapida({
    required this.icone,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: cor.withAlpha(25),
              child: Icon(icone, color: cor),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  final String valor;
  final String label;

  const _Metrica({required this.valor, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          valor,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _HistoricoTab extends StatelessWidget {
  final List<Map<String, Object?>> historico;

  const _HistoricoTab({required this.historico});

  @override
  Widget build(BuildContext context) {
    if (historico.isEmpty) {
      return const Center(child: Text('Nenhum atendimento realizado.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: historico.length,
      itemBuilder: (context, index) {
        final a = historico[index];
        final data = DateTime.parse(a['inicio'] as String);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PremiumCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(a['servico_nome'] as String? ?? 'Serviço'),
              subtitle: Text(
                '${data.day}/${data.month}/${data.year} • ${a['profissional_nome']}',
              ),
              trailing: Text(a['status'] as String),
            ),
          ),
        );
      },
    );
  }
}

class _FotosTab extends StatelessWidget {
  final List<FotoCliente> fotos;
  final VoidCallback onAdicionar;

  const _FotosTab({required this.fotos, required this.onAdicionar});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: fotos.isEmpty
          ? const Center(child: Text('Nenhuma foto adicionada.'))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: fotos.length,
              itemBuilder: (context, index) {
                final foto = fotos[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(
                      foto.thumbnailPath.isNotEmpty
                          ? foto.thumbnailPath
                          : foto.filePathLocal,
                    ),
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: onAdicionar,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}

class _ProdutosTab extends StatelessWidget {
  final List<Map<String, Object?>> compras;

  const _ProdutosTab({required this.compras});

  @override
  Widget build(BuildContext context) {
    if (compras.isEmpty) {
      return const Center(child: Text('Nenhuma compra registrada.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: compras.length,
      itemBuilder: (context, index) {
        final v = compras[index];
        final data = DateTime.parse(v['criada_em'] as String);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PremiumCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(
                'Venda ${v['numero']} • ${AppFormatters.moeda((v['total'] as num).toDouble())}',
              ),
              subtitle: Text(
                '${data.day}/${data.month}/${data.year}\n${v['itens'] ?? ''}',
              ),
              trailing: Text(v['status'] as String),
              isThreeLine: true,
            ),
          ),
        );
      },
    );
  }
}

class _AnotacoesTab extends StatefulWidget {
  final ClienteRegistro cliente;
  final ClienteRepository repository;
  final ValueChanged<ClienteRegistro> onAtualizado;

  const _AnotacoesTab({
    required this.cliente,
    required this.repository,
    required this.onAtualizado,
  });

  @override
  State<_AnotacoesTab> createState() => _AnotacoesTabState();
}

class _AnotacoesTabState extends State<_AnotacoesTab> {
  late TextEditingController _controller;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.cliente.observacoes);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final atualizado = widget.cliente.copiarCom(
      observacoes: _controller.text.trim(),
    );
    try {
      await widget.repository.atualizar(atualizado);
      widget.onAtualizado(atualizado);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Salvo com sucesso')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erro ao salvar')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Anotações livres sobre a cliente...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Salvar Anotações'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }
}
