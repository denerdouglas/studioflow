import 'package:flutter/material.dart';

import '../models/domain/centro_resultado.dart';
import '../repositories/centro_resultado_repository.dart';
import '../services/management_assistant_service.dart';
import 'pricing_assistant_page.dart';

class AssistenteGestaoPage extends StatefulWidget {
  final CentroResultado contexto;
  const AssistenteGestaoPage({
    super.key,
    this.contexto = CentroResultado.geral,
  });

  @override
  State<AssistenteGestaoPage> createState() => _AssistenteGestaoPageState();
}

class _AssistenteGestaoPageState extends State<AssistenteGestaoPage> {
  final input = TextEditingController();
  late final service = ManagementAssistantService(CentroResultadoRepository());
  String? answer;
  bool loading = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask([String? value]) async {
    final text = value ?? input.text;
    if (text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      final result = await service.responder(text, contexto: widget.contexto);
      if (mounted) setState(() => answer = result.texto);
    } catch (error) {
      if (mounted) setState(() => answer = 'Não foi possível analisar: $error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Assistente de Gestão')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Como posso ajudar?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in const [
              'Como estou hoje?',
              'Analisar este mês',
              'Analisar Salão',
              'Analisar Loja',
              'Quanto tenho a receber?',
            ])
              ActionChip(label: Text(prompt), onPressed: () => ask(prompt)),
            ActionChip(
              label: const Text('Precificar serviço'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PricingAssistantPage(servico: true),
                ),
              ),
            ),
            ActionChip(
              label: const Text('Precificar produto'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PricingAssistantPage(servico: false),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: input,
          decoration: InputDecoration(
            labelText: 'Pergunte sobre seu negócio',
            suffixIcon: IconButton(
              icon: const Icon(Icons.send),
              onPressed: ask,
            ),
          ),
          onSubmitted: ask,
        ),
        const SizedBox(height: 20),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (answer != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(answer!),
            ),
          ),
      ],
    ),
  );
}
