import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/helpers/app_formatters.dart';
import '../models/domain/atendimento.dart';
import '../repositories/cliente_360_repository.dart';
import '../repositories/pacotes_repository.dart';
import '../models/domain/pacote_servico.dart';

class Clientes360Page extends StatefulWidget {
  const Clientes360Page({super.key});
  @override
  State<Clientes360Page> createState() => _Clientes360PageState();
}

class _Clientes360PageState extends State<Clientes360Page> {
  final _repository = Cliente360Repository();
  List<Map<String, Object?>>? _clientes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final dados = await _repository.listarClientes();
    if (mounted) setState(() => _clientes = dados);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Clientes 360°')),
    body: _clientes == null
        ? const Center(child: CircularProgressIndicator())
        : _clientes!.isEmpty
        ? const Center(child: Text('Nenhum cliente cadastrado.'))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _clientes!.length,
            itemBuilder: (context, index) {
              final c = _clientes![index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      (c['nome'] as String).substring(0, 1).toUpperCase(),
                    ),
                  ),
                  title: Text(c['nome'] as String),
                  subtitle: Text(c['whatsapp'] as String? ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          Cliente360DetalhePage(clienteId: c['id'] as String),
                    ),
                  ),
                ),
              );
            },
          ),
  );
}

class Cliente360DetalhePage extends StatefulWidget {
  final String clienteId;
  const Cliente360DetalhePage({super.key, required this.clienteId});
  @override
  State<Cliente360DetalhePage> createState() => _Cliente360DetalhePageState();
}

class _Cliente360DetalhePageState extends State<Cliente360DetalhePage> {
  final _repository = Cliente360Repository();
  final _pacotesRepository = PacotesRepository();
  ResumoCliente360? _resumo;
  List<ResumoVendaPacote> _pacotes = [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _repository.carregar(widget.clienteId),
        _pacotesRepository.listarVendas(clienteId: widget.clienteId),
      ]);
      if (mounted) {
        setState(() {
          _resumo = resultados[0] as ResumoCliente360;
          _pacotes = resultados[1] as List<ResumoVendaPacote>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  Future<void> _abrirWhatsApp(String telefone) async {
    final numero = telefone.replaceAll(RegExp(r'\D'), '');
    if (numero.isEmpty) return;
    final url = Uri.parse('whatsapp://send?phone=55$numero');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final webUrl = Uri.parse('https://wa.me/55$numero');
      if (await canLaunchUrl(webUrl)) await launchUrl(webUrl);
    }
  }

  Future<void> _abrirInstagram(String handle) async {
    final user = handle.replaceAll('@', '').trim();
    if (user.isEmpty) return;
    final url = Uri.parse('instagram://user?username=$user');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      final webUrl = Uri.parse('https://instagram.com/$user');
      if (await canLaunchUrl(webUrl)) await launchUrl(webUrl);
    }
  }

  Future<void> _abrirTelefone(String telefone) async {
    final numero = telefone.replaceAll(RegExp(r'\D'), '');
    if (numero.isEmpty) return;
    final url = Uri.parse('tel:$numero');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumo;
    return Scaffold(
      appBar: AppBar(title: Text(r?.nome ?? 'Cliente 360°')),
      body: _erro != null
          ? Center(child: Text(_erro!))
          : r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.nome,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  Text(
                                    'Preferência: ${r.profissionalPreferido}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (r.whatsapp.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.message),
                                tooltip: 'WhatsApp',
                                onPressed: () => _abrirWhatsApp(r.whatsapp),
                              ),
                            if (r.instagram.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.camera_alt),
                                tooltip: 'Instagram',
                                onPressed: () => _abrirInstagram(r.instagram),
                              ),
                            if (r.telefone.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone),
                                tooltip: 'Telefone',
                                onPressed: () => _abrirTelefone(r.telefone),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _numero('Agendamentos', '${r.agendamentos}'),
                    _numero('Faltas', '${r.faltas}'),
                    _numero('Cancelamentos', '${r.cancelamentos}'),
                    _numero(
                      'Serviços',
                      AppFormatters.moeda(r.recebidoServicos),
                    ),
                    _numero('Produtos', AppFormatters.moeda(r.comprasProdutos)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pacotes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_pacotes.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Nenhum pacote vinculado.')),
                  ),
                ..._pacotes.map(
                  (pacote) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  pacote.pacoteNome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Chip(label: Text(pacote.status)),
                            ],
                          ),
                          LinearProgressIndicator(value: pacote.progresso),
                          const SizedBox(height: 6),
                          Text(
                            '${pacote.realizadas} de ${pacote.contratadas} sessões concluídas • ${pacote.disponiveis} disponíveis',
                          ),
                          Text(
                            'Pago: R\$ ${pacote.valorPago.toStringAsFixed(2)} • Pendente: R\$ ${pacote.valorPendente.toStringAsFixed(2)}',
                          ),
                          Text(
                            'Validade: ${pacote.validade != null ? '${pacote.validade!.day}/${pacote.validade!.month}/${pacote.validade!.year}' : 'vitalícia'}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Histórico de agenda',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (r.historicoAgenda.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Nenhum atendimento.')),
                  ),
                ...r.historicoAgenda.take(20).map((a) {
                  final data = DateTime.parse(a['inicio'] as String);
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: Text(a['servico_nome'] as String? ?? 'Serviço'),
                      subtitle: Text(
                        '${data.day}/${data.month}/${data.year} • ${a['profissional_nome']}',
                      ),
                      trailing: Text(a['status'] as String),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text(
                  'Compras na Loja do Salão',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (r.historicoCompras.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Nenhuma compra vinculada.')),
                  ),
                ...r.historicoCompras.take(20).map((v) {
                  final data = DateTime.parse(v['criada_em'] as String);
                  return Card(
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
                  );
                }),
              ],
            ),
    );
  }

  Widget _numero(String titulo, String valor) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(titulo, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
