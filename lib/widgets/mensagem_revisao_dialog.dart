import 'package:flutter/material.dart';

import '../services/external_action_service.dart';

Future<void> mostrarRevisaoMensagem(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String? telefone,
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
          child: const Text('Não enviar'),
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
        TextButton.icon(
          onPressed: () => externo.compartilhar(controller.text),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Compartilhar'),
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
