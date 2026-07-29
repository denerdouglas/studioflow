import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'backend_sync_service.dart';

class AutoSyncController {
  static final AutoSyncController instance = AutoSyncController._();

  AutoSyncController._();

  final BackendSyncService _service = BackendSyncService();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  String? _comercioId;
  bool _executando = false;

  Future<void> iniciar(String comercioId) async {
    if (_comercioId == comercioId && _subscription != null) return;
    await parar();
    _comercioId = comercioId;
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        unawaited(sincronizarAgora());
      }
    });
    unawaited(sincronizarAgora());
  }

  Future<void> sincronizarAgora() async {
    final comercioId = _comercioId;
    if (comercioId == null || _executando) return;
    _executando = true;
    try {
      await _service.sincronizar(comercioId);
    } on Object {
      // O serviço persiste a mensagem em integracoes_configuracao.
      // Ausência de rede nunca interrompe o funcionamento local.
    } finally {
      _executando = false;
    }
  }

  Future<void> parar() async {
    await _subscription?.cancel();
    _subscription = null;
    _comercioId = null;
  }
}
