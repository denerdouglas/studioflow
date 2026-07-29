import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/phone_normalizer.dart';

enum ResultadoWhatsApp { aberto, compartilhado, copiado }

class ExternalActionService {
  const ExternalActionService();

  Future<bool> abrirRota(Uri rota) async {
    final destino = rota.queryParameters['query'];
    if (destino != null && destino.trim().isNotEmpty) {
      for (final app in [
        Uri.parse('google.navigation:q=${Uri.encodeComponent(destino)}'),
        Uri.parse('waze://?q=${Uri.encodeComponent(destino)}&navigate=yes'),
      ]) {
        try {
          if (await launchUrl(app, mode: LaunchMode.externalApplication)) {
            return true;
          }
        } catch (_) {}
      }
    }
    if (await launchUrl(rota, mode: LaunchMode.externalApplication)) {
      return true;
    }
    return launchUrl(rota, mode: LaunchMode.platformDefault);
  }

  Future<void> compartilhar(String texto) async {
    await SharePlus.instance.share(ShareParams(text: texto));
  }

  Future<void> copiar(String texto) =>
      Clipboard.setData(ClipboardData(text: texto));

  Future<bool> ligar(String telefone) async {
    final numero = telefone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (numero.isEmpty) return false;
    return launchUrl(Uri(scheme: 'tel', path: numero));
  }

  Future<ResultadoWhatsApp> abrirWhatsApp({
    String? telefone,
    required String mensagem,
  }) async {
    final numero = PhoneNormalizer.paraWhatsapp(telefone);
    final parametros = <String, String>{'text': mensagem};
    if (numero != null) parametros['phone'] = numero;
    final app = Uri(
      scheme: 'whatsapp',
      host: 'send',
      queryParameters: parametros,
    );
    try {
      if (await launchUrl(app, mode: LaunchMode.externalApplication)) {
        return ResultadoWhatsApp.aberto;
      }
    } catch (_) {}

    final web = numero == null
        ? Uri.https('wa.me', '/', {'text': mensagem})
        : Uri.https('wa.me', '/$numero', {'text': mensagem});
    try {
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) {
        return ResultadoWhatsApp.aberto;
      }
    } catch (_) {}

    await copiar(mensagem);
    try {
      await compartilhar(mensagem);
      return ResultadoWhatsApp.compartilhado;
    } catch (_) {
      return ResultadoWhatsApp.copiado;
    }
  }
}
