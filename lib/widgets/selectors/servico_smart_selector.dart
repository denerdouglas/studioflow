import 'package:flutter/material.dart';
import '../../repositories/servicos_repository.dart';
import '../smart_selector.dart';
import '../../screens/servicos_page.dart';

class ServicoSmartSelector {
  static Future<ServicoRegistro?> show(BuildContext context) async {
    final repository = ServicosRepository();
    
    return SmartSelector.show<ServicoRegistro>(
      context: context,
      title: 'Selecionar Serviço',
      searchHint: 'Buscar por nome, categoria...',
      onSearch: (query, offset, limit) async {
        return repository.pesquisar(query, incluirInativos: false, limit: limit, offset: offset);
      },
      itemBuilder: (context, servico) {
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFF0EBF7),
            child: const Icon(Icons.content_cut, color: Color(0xFF70569A), size: 20),
          ),
          title: Text(servico.nome),
          subtitle: Text('${servico.categoria} • ${servico.duracaoMinutos} min'),
          trailing: Text(
            'R\$ ${servico.preco.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
      onCreateNew: (ctx) async {
        final novoServico = await showModalBottomSheet<ServicoRegistro>(
          context: ctx,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const ServicoFormSheet(),
        );

        if (novoServico != null) {
          try {
            await repository.salvar(novoServico);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Serviço cadastrado com sucesso.')),
              );
            }
            return novoServico;
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('Erro ao salvar serviço: $e')),
              );
            }
          }
        }
        return null;
      },
    );
  }
}
