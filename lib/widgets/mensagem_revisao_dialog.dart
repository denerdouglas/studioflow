import 'package:flutter/material.dart';

import '../services/external_action_service.dart';

Future<void> mostrarRevisaoMensagem(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String? telefone,
  Future<void> Function(String mensagem)? onEnqueue,
}) async {
  final controller = TextEditingController(text: mensagem);
  const externo = ExternalActionService();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: controller,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: 'Revise e edite antes de enviar',
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        TextButton.icon(
          onPressed: () async {
            await externo.copiar(controller.text);
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Mensagem copiada.')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copiar'),
        ),
        if (onEnqueue != null)
          FilledButton.icon(
            onPressed: () async {
              await onEnqueue(controller.text);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Mensagem na fila de disparo automático.')),
                );
              }
            },
            icon: const Icon(Icons.schedule_send),
            label: const Text('Enfileirar (Automático)'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00C853)),
          ),
        FilledButton.icon(
          onPressed: () async {
            final resultado = await externo.abrirWhatsApp(
              telefone: telefone,
              mensagem: controller.text,
            );
            if (dialogContext.mounted &&
                resultado != ResultadoWhatsApp.aberto) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Mensagem copiada. Cole no aplicativo de sua preferência.',
                  ),
                ),
              );
            } else if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
          },
          icon: const Icon(Icons.chat_outlined),
          label: const Text('Enviar agora'),
        ),
      ],
    ),
  );
  controller.dispose();
}
