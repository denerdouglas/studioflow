import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/booking_settings_repository.dart';
import '../services/external_action_service.dart';

class AgendamentoOnlinePage extends StatefulWidget {
  const AgendamentoOnlinePage({super.key});
  @override
  State<AgendamentoOnlinePage> createState() => _AgendamentoOnlinePageState();
}

class _AgendamentoOnlinePageState extends State<AgendamentoOnlinePage> {
  final _repository = BookingSettingsRepository();
  final _slug = TextEditingController();
  BookingSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _slug.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = await _repository.load();
      if (!mounted) return;
      setState(() {
        _settings = value;
        _slug.text = value.slug;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _message('$error');
      }
    }
  }

  Future<void> _save({bool? enabled}) async {
    try {
      final value = await _repository.update(
        slug: _slug.text.trim(),
        enabled: enabled ?? _settings!.enabled,
      );
      if (!mounted) return;
      setState(() {
        _settings = value;
        _slug.text = value.slug;
      });
      _message('Agendamento online atualizado.');
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Agendamento Online')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : settings == null
          ? const Center(child: Text('Configuração indisponível.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Agendamento público ativo'),
                  subtitle: Text(
                    settings.enabled
                        ? 'Clientes podem reservar horários.'
                        : 'O link permanece reservado, mas a página fica indispon?vel.',
                  ),
                  value: settings.enabled,
                  onChanged: (value) => _save(enabled: value),
                ),
                TextField(
                  controller: _slug,
                  decoration: const InputDecoration(
                    labelText: 'Endereço público',
                    prefixText: 'studioflowapp.com.br/agendar/',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar endereço'),
                ),
                const SizedBox(height: 24),
                SelectableText(settings.publicUrl, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Center(
                  child: QrImageView(
                    data: settings.publicUrl,
                    size: 220,
                    semanticsLabel: 'QR Code do agendamento online',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: settings.publicUrl),
                        );
                        if (mounted) _message('Link copiado.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(text: settings.publicUrl),
                      ),
                      icon: const Icon(Icons.share),
                      label: const Text('Compartilhar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          const ExternalActionService().abrirWhatsApp(
                            telefone: null,
                            mensagem:
                                'Agende seu horário: ${settings.publicUrl}',
                          ),
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: 'Agende pelo link ${settings.publicUrl}',
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Instagram'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(settings.publicUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Visualizar'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
