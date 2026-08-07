import 'package:flutter/material.dart';
import '../../repositories/cliente_repository.dart';
import '../smart_selector.dart';
import '../../screens/clientes_page.dart';

class ClienteSmartSelector {
  static Future<ClienteRegistro?> show(BuildContext context) async {
    final repository = ClienteRepository();

    return SmartSelector.show<ClienteRegistro>(
      context: context,
      title: 'Selecionar Cliente',
      searchHint: 'Buscar por nome, celular...',
      onSearch: (query, offset, limit) async {
        return repository.buscarPesquisando(
          query,
          limit: limit,
          offset: offset,
        );
      },
      itemBuilder: (context, cliente) {
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFF0EBF7),
            child: Text(
              cliente.nome.substring(0, 1).toUpperCase(),
              style: const TextStyle(color: Color(0xFF70569A)),
            ),
          ),
          title: Text(cliente.nome),
          subtitle: Text(cliente.whatsapp),
        );
      },
      onCreateNew: (ctx) async {
        final novoCliente = await showModalBottomSheet<ClienteRegistro>(
          context: ctx,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const CadastroClienteSheet(),
        );

        if (novoCliente != null) {
          try {
            await repository.inserir(novoCliente);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('Cliente cadastrado com sucesso.'),
                ),
              );
            }
            return novoCliente;
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('Erro ao salvar cliente: $e')),
              );
            }
          }
        }
        return null;
      },
    );
  }
}
