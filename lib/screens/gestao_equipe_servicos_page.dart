import 'package:flutter/material.dart';

import 'funcionarios_page.dart';
import 'pacotes_page.dart';
import 'servicos_page.dart';

class EquipeComissoesPage extends StatelessWidget {
  const EquipeComissoesPage({super.key});

  @override
  Widget build(BuildContext context) => const FuncionariosPage();
}

class ServicosPacotesPage extends StatefulWidget {
  const ServicosPacotesPage({super.key});

  @override
  State<ServicosPacotesPage> createState() => _ServicosPacotesPageState();
}

class _ServicosPacotesPageState extends State<ServicosPacotesPage> {
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serviços e Pacotes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.design_services_outlined),
                  label: Text('Serviços'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.card_giftcard_outlined),
                  label: Text('Pacotes'),
                ),
              ],
              selected: {_indice},
              onSelectionChanged: (value) =>
                  setState(() => _indice = value.first),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _indice,
        children: const [ServicosPage(), PacotesPage()],
      ),
    );
  }
}
