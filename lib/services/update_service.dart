import 'dart:convert';
import 'package:http/http.dart' as http;
import 'acesso_online_service.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'notification_service.dart';

class UpdateInfo {
  final int minBuild;
  final int latestBuild;
  final String latestVersion;
  final String storeUrl;
  final bool forceUpdate;
  final String message;

  const UpdateInfo({
    required this.minBuild,
    required this.latestBuild,
    required this.latestVersion,
    required this.storeUrl,
    required this.forceUpdate,
    required this.message,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final android = json['android'] as Map<String, dynamic>;
    return UpdateInfo(
      minBuild: android['min_build'] as int? ?? 0,
      latestBuild: android['latest_build'] as int? ?? 0,
      latestVersion: android['latest_version'] as String? ?? '',
      storeUrl:
          android['store_url'] as String? ??
          'https://play.google.com/store/apps/details?id=com.rolgsystems.studioflow',
      forceUpdate: android['force_update'] as bool? ?? false,
      message:
          android['message'] as String? ??
          'Nova atualiza\u00e7\u00e3o dispon\u00edvel',
    );
  }
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  UpdateInfo? _latestInfo;
  http.Client? _client;

  // Injeta client de teste se precisar
  void setClient(http.Client client) {
    _client = client;
  }

  // Faz a chamada real para o endpoint publico do backend
  Future<UpdateInfo?> fetchRemoteUpdateInfo() async {
    try {
      final endpointStr = AcessoOnlineService.endpointCompilado;
      if (endpointStr.isEmpty) return null;

      final uri = Uri.parse(endpointStr).replace(path: '/v1/public/app-config');
      final client = _client ?? http.Client();

      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        _latestInfo = UpdateInfo.fromJson(json);
        return _latestInfo;
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao buscar configuracao de versao: $e');
      return null;
    }
  }

  Future<void> checkForUpdates(
    BuildContext context, {
    bool fromBackground = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // No background/on start, valida cache e a opcao "Lembrar depois"
    if (fromBackground) {
      final lastPromptedBuild = prefs.getInt('last_prompted_build') ?? 0;
      final lastCheckedTime = prefs.getInt('last_checked_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Evita bater no "backend" o tempo todo (cache de 6 horas)
      if (now - lastCheckedTime < const Duration(hours: 6).inMilliseconds) {
        if (_latestInfo != null &&
            lastPromptedBuild >= _latestInfo!.latestBuild) {
          return;
        }
      }
    }

    final info = await fetchRemoteUpdateInfo();
    if (info == null) return; // offline ou falha, nao quebra app

    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

    if (info.latestBuild > currentBuild) {
      // Avisa via notificacao quando existe nova versao
      if (fromBackground) {
        await NotificationService().showNotification(
          id: 9999,
          title: 'Nova vers\u00e3o do StudioFlow',
          body: info.message,
        );
      }

      if (context.mounted) {
        final lastPromptedBuild = prefs.getInt('last_prompted_build') ?? 0;

        // Evita repetir o aviso para a mesma build apos "Lembrar depois"
        if (!info.forceUpdate &&
            lastPromptedBuild == info.latestBuild &&
            fromBackground) {
          return;
        }

        await _showUpdateDialog(context, info, packageInfo, currentBuild);
      }
    }

    await prefs.setInt(
      'last_checked_time',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _showUpdateDialog(
    BuildContext context,
    UpdateInfo info,
    PackageInfo packageInfo,
    int currentBuild,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final isForced = currentBuild < info.minBuild || info.forceUpdate;

    await showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (context) {
        return PopScope(
          canPop: !isForced,
          child: AlertDialog(
            title: const Text('NOVA ATUALIZA\u00c7\u00c3O DISPON\u00cdVEL'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('StudioFlow ${info.latestVersion}'),
                const SizedBox(height: 8),
                Text(
                  isForced
                      ? 'Esta versão não é mais suportada.'
                      : 'Atualize o aplicativo para receber:\n- correções;\n- melhorias;\n- novas funcionalidades.',
                ),
              ],
            ),
            actions: [
              if (!isForced)
                TextButton(
                  onPressed: () {
                    prefs.setInt('last_prompted_build', info.latestBuild);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('LEMBRAR DEPOIS'),
                ),
              FilledButton(
                onPressed: () async {
                  final url = Uri.parse(info.storeUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    debugPrint('N\u00e3o foi poss\u00edvel abrir a loja.');
                  }
                },
                child: Text(isForced ? 'ATUALIZAR' : 'ATUALIZAR AGORA'),
              ),
            ],
          ),
        );
      },
    );
  }
}
