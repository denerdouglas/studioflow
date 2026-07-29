import 'package:flutter/material.dart';

import '../repositories/comissoes_repository.dart';

const Color kComissaoPrincipal = Color(0xFF70569A);

const Color kComissaoFundo = Color(0xFFF9F6FC);

const Color kComissaoTexto = Color(0xFF2D2140);

const Color kComissaoCinza = Color(0xFF766A85);

const Color kComissaoVerde = Color(0xFF15996B);

const Color kComissaoLaranja = Color(0xFFE58A25);

class ComissoesPage extends StatefulWidget {
  const ComissoesPage({super.key});

  @override
  State<ComissoesPage> createState() => _ComissoesPageState();
}

class _ComissoesPageState extends State<ComissoesPage> {
  final ComissoesRepository repository = ComissoesRepository();

  List<ComissaoRegistro> registros = [];

  bool carregando = true;

  double totalPago = 0;

  double totalPendente = 0;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final lista = await repository.listar();

    final pago = await repository.totalPago();

    final pendente = await repository.totalPendente();

    if (!mounted) {
      return;
    }

    setState(() {
      registros = lista;
      totalPago = pago;
      totalPendente = pendente;
      carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComissaoFundo,
      appBar: AppBar(
        backgroundColor: kComissaoFundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Comissões',
          style: TextStyle(color: kComissaoTexto, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: carregar,
            icon: const Icon(Icons.refresh, color: kComissaoPrincipal),
          ),
        ],
      ),
      body: Column(
        children: [
          _cabecalho(),
          Expanded(
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : _lista(),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF70569A), Color(0xFF9A78C5)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total pago', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(
              'R\$ ${totalPago.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Pendente: '
              'R\$ ${totalPendente.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    if (registros.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.percent, size: 70, color: Colors.grey),
            SizedBox(height: 18),
            Text(
              'Nenhuma comissão encontrada.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kComissaoPrincipal,
      onRefresh: carregar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
        itemCount: registros.length,
        itemBuilder: (_, index) {
          final item = registros[index];

          final pago = item.status == 'pago';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE6DFF0)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: pago
                      ? kComissaoVerde.withValues(alpha: 0.15)
                      : kComissaoLaranja.withValues(alpha: 0.15),
                  child: Icon(
                    Icons.percent,
                    color: pago ? kComissaoVerde : kComissaoLaranja,
                  ),
                ),
                title: Text(
                  'Comissão',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${item.percentualComissao.toStringAsFixed(0)}% • '
                  'R\$ ${item.valorComissao.toStringAsFixed(2)}',
                ),
                trailing: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: pago ? kComissaoLaranja : kComissaoVerde,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (pago) {
                      await repository.marcarComoPendente(item.id);
                    } else {
                      await repository.marcarComoPaga(item.id);
                    }

                    carregar();
                  },
                  child: Text(pago ? 'Pendente' : 'Pagar'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
