import 'package:flutter/material.dart';

import '../core/helpers/app_formatters.dart';
import '../services/ia_local_service.dart';
import '../services/session_controller.dart';

class IaLocalPage extends StatefulWidget {
  const IaLocalPage({super.key});

  @override
  State<IaLocalPage> createState() => _IaLocalPageState();
}

class _IaLocalPageState extends State<IaLocalPage> {
  final IaStudioFlowProvider _ia = IaLocalService();
  ResumoIaLocal? _resumo;
  String? _erro;

  static const _perguntas = [
    'Como está minha agenda hoje?',
    'Quantos clientes estão cadastrados?',
    'Quais horários estão livres?',
    'Qual serviço aparece mais?',
    'Como estão as vendas e recebimentos?',
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final comercioId = SessionController.instance.usuario!.comercioId;
      final resumo = await _ia.gerarResumo(comercioId);
      if (mounted) setState(() => _resumo = resumo);
    } catch (erro) {
      if (mounted) {
        setState(() => _erro = 'Nao foi possivel analisar os dados locais.');
      }
    }
  }

  void _perguntar(String pergunta) {
    final resumo = _resumo;
    if (resumo == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pergunta),
        content: Text(_ia.responder(pergunta, resumo)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('StudioFlow IA local'),
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _erro != null
          ? Center(child: Text(_erro!))
          : resumo == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'Resumo com dados reais deste aparelho',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _indicador(
                        'Clientes',
                        resumo.clientes.toString(),
                        Icons.people,
                      ),
                      _indicador(
                        'Agenda hoje',
                        resumo.agendamentosHoje.toString(),
                        Icons.calendar_today,
                      ),
                      _indicador(
                        'Livres',
                        resumo.horariosLivres.length.toString(),
                        Icons.schedule,
                      ),
                      _indicador(
                        'Recebido no mês',
                        AppFormatters.moeda(resumo.recebidoMes),
                        Icons.payments,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _secao('Alertas', resumo.alertas, Icons.warning_amber),
                  _secao(
                    'Sugestões',
                    resumo.sugestoes,
                    Icons.lightbulb_outline,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Perguntas rápidas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ..._perguntas.map(
                    (pergunta) => Card(
                      child: ListTile(
                        title: Text(pergunta),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () => _perguntar(pergunta),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Esta versão funciona totalmente no aparelho. Uma futura IA online deverá usar backend seguro; nenhuma chave de API está incluída no aplicativo.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _indicador(String titulo, String valor, IconData icone) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 46) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icone, color: const Color(0xFF70569A)),
              const SizedBox(height: 8),
              Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(titulo, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secao(String titulo, List<String> itens, IconData icone) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (itens.isEmpty) const Text('Nenhum item importante agora.'),
            ...itens.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
