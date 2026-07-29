import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repositories/privacy_repository.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  final _repository = PrivacyRepository();
  bool _pendingDeletion = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pending = await _repository.hasPendingDeletionRequest();
    if (mounted) setState(() => _pendingDeletion = pending);
  }

  Future<void> _export() async {
    final data = await _repository.exportCurrentUserData();
    await Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seus dados foram copiados em formato JSON.'),
        ),
      );
    }
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar exclusão da conta?'),
        content: const Text(
          'A solicitação será registrada. Os dados não serão apagados imediatamente no aparelho para evitar perda acidental; a conclusão exige confirmação segura do titular e do backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar solicitação'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.requestAccountDeletion();
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacidade e LGPD')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'O StudioFlow mantém os dados operacionais separados por comércio. O catálogo compartilhado recebe somente dados gerais de produto quando há consentimento. Preços, estoque, fornecedores, vendas e informações financeiras permanecem privados.',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Exportar meus dados'),
            subtitle: const Text(
              'Copia os dados cadastrais do usuário e do comércio em JSON.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _export,
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              _pendingDeletion ? Icons.schedule : Icons.delete_outline,
              color: Colors.red,
            ),
            title: Text(
              _pendingDeletion
                  ? 'Exclusão solicitada'
                  : 'Solicitar exclusão da conta',
            ),
            subtitle: Text(
              _pendingDeletion
                  ? 'A solicitação está pendente de confirmação segura.'
                  : 'Registra a solicitação sem apagar dados acidentalmente.',
            ),
            onTap: _pendingDeletion ? null : _requestDeletion,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Permissões usadas: câmera somente para leitura de códigos. Localização, contatos e arquivos não são solicitados nesta versão.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    ),
  );
}
