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
              'O StudioFlow mantém os dados operacionais rigorosamente separados por comércio. Suas informações financeiras, fluxo de caixa, vendas, fornecedores, clientes e estoque permanecem estritamente privadas e não são compartilhadas.\n\n'
              'O catálogo global opcional recebe apenas metadados públicos do produto (GTIN, descrição básica, categoria) para facilitar o cadastro para outros usuários, mas nunca seus custos ou preços.',
            ),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Funcionalidades e Integrações:\n'
              '• Sincronização e Modo Offline: Seus dados são salvos localmente (SQLite) para funcionamento sem internet e, quando online, sincronizados de forma segura (HTTPS) com a nuvem.\n'
              '• Marketplace e Acadêmico: Estes módulos conectam você a ofertas e cursos de parceiros (ex: Hotmart, Amazon, Shopee). Acessar essas ofertas utiliza redirecionamentos monitorados e links de afiliados, que podem instalar cookies de terceiros em seu navegador/aplicativo externo, sujeitos às políticas dessas plataformas.\n'
              '• Pagamentos e Assinaturas: O StudioFlow não processa, não armazena e não tem acesso aos dados sensíveis do seu cartão de crédito. As transações são gerenciadas exclusivamente pelas lojas oficiais (Google Play) ou gateways parceiros.',
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
                  : 'Registra a solicitação de remoção definitiva dos dados.',
            ),
            onTap: _pendingDeletion ? null : _requestDeletion,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Permissões: A câmera é solicitada apenas para a leitura de códigos de barras (GTIN) e QR Codes. Localização, lista de contatos e arquivos do dispositivo não são acessados pelo aplicativo nesta versão.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    ),
  );
}
