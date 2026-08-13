import 'scanner_product_draft.dart';

enum ReaderContext {
  cadastro,
  venda,
  estoque,
  recebimentoFornecedor,
  consignacao,
  conferenciaRemessa,
  importacao,
}

enum ReaderAction {
  incrementar,
  decrementar,
  vender,
  editar,
  conferir,
  inativar,
  adicionarRascunho,
  ignorar,
}

class ReaderContextPolicy {
  final ReaderContext context;
  final Set<ReaderAction> allowedActions;
  final bool continuous;
  final bool persistsOnRead;

  const ReaderContextPolicy({
    required this.context,
    required this.allowedActions,
    this.continuous = false,
    this.persistsOnRead = false,
  });

  factory ReaderContextPolicy.forContext(ReaderContext context) {
    final batch = const {
      ReaderAction.editar,
      ReaderAction.conferir,
      ReaderAction.adicionarRascunho,
      ReaderAction.ignorar,
    };
    return ReaderContextPolicy(
      context: context,
      continuous: const {
        ReaderContext.estoque,
        ReaderContext.recebimentoFornecedor,
        ReaderContext.consignacao,
        ReaderContext.conferenciaRemessa,
      }.contains(context),
      allowedActions: switch (context) {
        ReaderContext.venda => const {
          ReaderAction.vender,
          ReaderAction.editar,
          ReaderAction.conferir,
          ReaderAction.ignorar,
        },
        ReaderContext.estoque => const {
          ReaderAction.incrementar,
          ReaderAction.decrementar,
          ReaderAction.editar,
          ReaderAction.conferir,
          ReaderAction.inativar,
          ReaderAction.adicionarRascunho,
          ReaderAction.ignorar,
        },
        _ => batch,
      },
    );
  }
}

class BipSessionItem {
  final String id;
  final String deduplicationKey;
  final ScannerProductDraft draft;
  final bool confirmed;
  final bool ignored;

  const BipSessionItem({
    required this.id,
    required this.deduplicationKey,
    required this.draft,
    this.confirmed = false,
    this.ignored = false,
  });

  BipSessionItem copyWith({
    ScannerProductDraft? draft,
    bool? confirmed,
    bool? ignored,
  }) => BipSessionItem(
    id: id,
    deduplicationKey: deduplicationKey,
    draft: draft ?? this.draft,
    confirmed: confirmed ?? this.confirmed,
    ignored: ignored ?? this.ignored,
  );
}

class BipSessionCounters {
  final int read;
  final int confirmed;
  final int duplicates;
  final int errors;
  final int pendingReview;

  const BipSessionCounters({
    required this.read,
    required this.confirmed,
    required this.duplicates,
    required this.errors,
    required this.pendingReview,
  });
}

class BipSessionController {
  final List<BipSessionItem> _items = [];
  int _duplicates = 0;
  int _errors = 0;

  List<BipSessionItem> get items => List.unmodifiable(_items);

  BipSessionCounters get counters => BipSessionCounters(
    read: _items.length,
    confirmed: _items.where((item) => item.confirmed).length,
    duplicates: _duplicates,
    errors: _errors,
    pendingReview: _items
        .where((item) => !item.ignored && item.draft.precisaRevisao)
        .length,
  );

  bool add(BipSessionItem item) {
    if (_items.any(
      (existing) => existing.deduplicationKey == item.deduplicationKey,
    )) {
      _duplicates++;
      return false;
    }
    _items.add(item);
    return true;
  }

  void registerError() => _errors++;

  void update(String id, ScannerProductDraft draft) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Leitura temporária não encontrada.');
    _items[index] = _items[index].copyWith(draft: draft);
  }

  void confirm(String id) => _set(id, confirmed: true, ignored: false);
  void ignore(String id) => _set(id, ignored: true, confirmed: false);

  void remove(String id) => _items.removeWhere((item) => item.id == id);

  void _set(String id, {bool? confirmed, bool? ignored}) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Leitura temporária não encontrada.');
    _items[index] = _items[index].copyWith(
      confirmed: confirmed,
      ignored: ignored,
    );
  }
}
