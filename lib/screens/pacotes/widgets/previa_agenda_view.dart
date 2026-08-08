import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/domain/pacote_servico.dart';

class PreviaAgendaView extends StatelessWidget {
  final PreviaAgendaPacote previa;
  final void Function(int, SessaoPlanejadaPacote)? onEditSessao;

  const PreviaAgendaView({super.key, required this.previa, this.onEditSessao});

  @override
  Widget build(BuildContext context) {
    if (previa.sessoes.isEmpty && previa.naoEncaixadas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prévia de Agendamentos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (previa.naoEncaixadas.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Conflitos Encontrados',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...previa.naoEncaixadas.map(
                      (falha) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          falha,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (previa.sessoes.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: previa.sessoes.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final s = previa.sessoes[index];
                  final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${index + 1}. ${s.servicoNome}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${dateFormat.format(s.inicio)} - ${s.profissionalNome}',
                        ),
                        if (s.aviso != null)
                          Text(
                            s.aviso!,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onEditSessao != null)
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => onEditSessao!(index, s),
                          ),
                        s.horarioAlternativo
                            ? const Icon(
                                Icons.info_outline,
                                color: Colors.orange,
                              )
                            : const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                              ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
