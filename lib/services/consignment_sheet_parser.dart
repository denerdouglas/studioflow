import '../models/domain/consignment_document_import.dart';

class ConsignmentSheetParser {
  static final _categoryPattern = RegExp(
    r'^\s*\d{3}\s*[-–]\s*(.+?)\s*$',
    caseSensitive: false,
  );
  static final _materialPattern = RegExp(
    r'^\s*\*{2,}\s*([^\s]+)',
    caseSensitive: false,
  );

  static ConsignmentDocumentImport parse(String text) {
    final rawLines = text.replaceAll('\u00a0', ' ').split(RegExp(r'\r?\n'));
    final lines = rawLines
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    String? category;
    String? material;
    final items = <ConsignmentImportItem>[];
    final pending = <ConsignmentPendingLine>[];

    for (var rawIndex = 0; rawIndex < rawLines.length; rawIndex++) {
      final line = rawLines[rawIndex].replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty) continue;
      final categoryMatch = _categoryPattern.firstMatch(line);
      if (categoryMatch != null) {
        category = _title(
          categoryMatch
              .group(1)!
              .replaceFirst(
                RegExp(r'\s+\d+\s+itens?\s*$', caseSensitive: false),
                '',
              ),
        );
        continue;
      }
      final materialMatch = _materialPattern.firstMatch(line);
      if (materialMatch != null) {
        material = _title(materialMatch.group(1)!);
      }

      if (_isHeader(line)) continue;

      // Universal item parsing
      final lineClean = line.replaceAll(RegExp(r'\s*\|\s*'), ' ');

      // Procurar por preço e quantidade
      final pricePattern = RegExp(r'(?:R\$\s*)?(\d{1,6}[.,]\d{2})(?!\d)');
      final qtyPattern = RegExp(r'(?<!\d[.,])\b(\d{1,4})\b(?![.,]\d)');

      var remainingLine = lineClean;
      var foundAnyItem = false;

      while (true) {
        final priceMatch = pricePattern.firstMatch(remainingLine);
        if (priceMatch == null) break;

        final priceStr = priceMatch.group(1)!;
        final price = _brazilianMoney(priceStr);

        // A parte da string ANTES do preço + o próprio preço é o chunk atual
        final chunk = remainingLine.substring(0, priceMatch.end);
        remainingLine = remainingLine.substring(priceMatch.end).trim();

        // Remover o preço do chunk para procurar a quantidade e código
        var chunkSemPreco = chunk.replaceFirst(priceMatch.group(0)!, '').trim();

        var qty = 1;
        final qtyMatches = qtyPattern.allMatches(chunkSemPreco).toList();
        if (qtyMatches.isNotEmpty) {
          RegExpMatch bestMatch = qtyMatches.last;
          for (final m in qtyMatches) {
            if (int.parse(m.group(1)!) < 100) {
              bestMatch = m;
            }
          }
          qty = int.parse(bestMatch.group(1)!);
          chunkSemPreco = chunkSemPreco
              .replaceRange(bestMatch.start, bestMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }

        final parts = chunkSemPreco
            .split(' ')
            .where((e) => e.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          String codigo = '';
          String descricao = '';

          final maybeCodeLast = parts.last;
          final maybeCodeFirst = parts.first;

          if (RegExp(r'^\d+$').hasMatch(maybeCodeLast) ||
              (maybeCodeLast.length <= 6 &&
                  RegExp(r'\d').hasMatch(maybeCodeLast))) {
            codigo = maybeCodeLast;
            parts.removeLast();
            descricao = parts.join(' ');
          } else if (RegExp(r'^\d+$').hasMatch(maybeCodeFirst) ||
              (maybeCodeFirst.length <= 6 &&
                  RegExp(r'\d').hasMatch(maybeCodeFirst))) {
            codigo = maybeCodeFirst;
            parts.removeAt(0);
            descricao = parts.join(' ');
          } else {
            codigo = parts.length > 1 ? parts.removeLast() : parts.first;
            descricao = parts.join(' ');
          }

          if (descricao.isEmpty) descricao = category ?? '';

          items.add(
            ConsignmentImportItem(
              codigo: codigo,
              categoria: category ?? '',
              material: material ?? '',
              quantidade: qty,
              valorUnitario: price,
              descricao: descricao.isNotEmpty
                  ? _title(descricao)
                  : (category ?? ''),
            ),
          );
          foundAnyItem = true;
        }
      }

      if (foundAnyItem) continue;

      if (RegExp(r'\d{4,}').hasMatch(line) && !_isHeader(line)) {
        pending.add(
          ConsignmentPendingLine(
            lineNumber: rawIndex + 1,
            originalText: line,
            reason: _pendingReason(line),
          ),
        );
      }
    }

    if (items.isEmpty && text.contains('\n')) {
      final dataLines = rawLines
          .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((line) => line.isNotEmpty && !_isHeader(line))
          .toList();
      if (dataLines.length > 1) {
        final joinedText = dataLines.join('  ');
        final fallbackParsed = parse(joinedText);
        if (fallbackParsed.itens.isNotEmpty) {
          items.addAll(fallbackParsed.itens);
          pending.clear();
          pending.addAll(fallbackParsed.linhasPendentes);
        }
      }
    }

    return ConsignmentDocumentImport(
      representante: _representative(lines),
      contrato: _header(lines, const ['CONTRATO']),
      mostruario: _showcase(lines),
      dataEnvio: _documentDates(lines).$1,
      dataTroca: _documentDates(lines).$2,
      dataPagamento: _documentDates(lines).$3,
      zonaVenda: _header(lines, const ['ZONA VENDA', 'ZONA DE VENDA', 'ZONA']),
      itens: items,
      linhasPendentes: pending,
      quantidadeDeclarada: _declaredTotal(lines).$1,
      totalDeclarado: _declaredTotal(lines).$2,
    );
  }

  static String _pendingReason(String line) {
    if (RegExp(
      r'(?:R\$\s*)?\?+[.,]?\d*|\d+[.,]\?+',
      caseSensitive: false,
    ).hasMatch(line)) {
      return 'Valor não reconhecido';
    }
    if (RegExp(
      r'\b(?:QTD|QUANTIDADE)\b|\?+\s+\d+[.,]\d{2}',
      caseSensitive: false,
    ).hasMatch(line)) {
      return 'Quantidade ambígua';
    }
    return 'Estrutura não reconhecida';
  }

  static double _brazilianMoney(String value) => double.parse(
    value.contains(',')
        ? value.replaceAll('.', '').replaceAll(',', '.')
        : value,
  );

  static String? _representative(List<String> lines) {
    final direct = _header(lines, const [
      'FORNECEDOR',
      'REPRESENTANTE',
      'REPRESENT',
    ]);
    if (direct != null &&
        !RegExp(
          r'^(?:VAL|QTD|PRODUTO)\b',
          caseSensitive: false,
        ).hasMatch(direct)) {
      return direct;
    }
    for (final line in lines) {
      if (!_normalize(line).contains('REPRESENT') &&
          !_normalize(line).contains('FORNECEDOR')) {
        continue;
      }
      final cleaned = line
          .replaceAll(RegExp(r'REPRESENT(?:ANTE)?', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'FORNECEDOR', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'DATA\s*ENVIO', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'^\s*\d+\s*'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (RegExp(r'[A-Za-zÀ-ÿ]{2}').hasMatch(cleaned)) return cleaned;
    }
    return direct;
  }

  static String? _showcase(List<String> lines) {
    final direct = _header(lines, const ['MOSTRUÁRIO', 'MOSTRUARIO']);
    if (direct != null &&
        RegExp(r'\d').hasMatch(direct) &&
        _categoryPattern.firstMatch(direct) == null &&
        !RegExp(r'\bITENS?\b', caseSensitive: false).hasMatch(direct)) {
      return direct;
    }
    final header = lines.takeWhile(
      (line) => _categoryPattern.firstMatch(line) == null,
    );
    for (final line in header) {
      final match = RegExp(r'(?<!\d)(\d{1,3}\.\d{3})(?!\d)').firstMatch(line);
      if (match != null) return match.group(1);
    }
    return direct;
  }

  static (DateTime?, DateTime?, DateTime?) _documentDates(List<String> lines) {
    final envio = _dateHeader(lines, const ['DATA ENVIO']);
    final troca = _dateHeader(lines, const ['DATA TROCA', 'TROCA']);
    final pagamento = _dateHeader(lines, const [
      'DATA PAGTO',
      'DATA PAGAMENTO',
      'PAGTO',
    ]);
    if (envio != null && troca != null && pagamento != null) {
      return (envio, troca, pagamento);
    }
    final header = lines.takeWhile(
      (line) => _categoryPattern.firstMatch(line) == null,
    );
    final dates = <DateTime>{};
    final pattern = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})');
    for (final line in header) {
      for (final match in pattern.allMatches(line)) {
        var year = int.parse(match.group(3)!);
        if (year < 100) year += 2000;
        dates.add(
          DateTime(
            year,
            int.parse(match.group(2)!),
            int.parse(match.group(1)!),
          ),
        );
      }
    }
    final ordered = dates.toList()..sort();
    if (ordered.length >= 3) return (ordered[0], ordered[1], ordered[2]);
    return (envio, troca, pagamento);
  }

  static String? _header(List<String> lines, List<String> labels) {
    const allLabels = [
      'FORNECEDOR',
      'REPRESENTANTE',
      'REPRESENT',
      'MOSTRUARIO',
      'CONTRATO',
      'DATA ENVIO',
      'DATA TROCA',
      'DATA PAGAMENTO',
      'DATA PAGTO',
      'ZONA DE VENDA',
      'ZONA VENDA',
    ];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final upper = _normalize(line);
      for (final label in labels) {
        final normalizedLabel = _normalize(label);
        final labelIndex = upper.indexOf(normalizedLabel);
        if (labelIndex < 0) continue;
        final valueStart = labelIndex + normalizedLabel.length;
        var valueEnd = line.length;
        for (final other in allLabels) {
          if (other == label) continue;
          final otherNormalized = _normalize(other);
          // Look for other label as a distinct key, usually followed by : or -
          final otherPattern = RegExp('\\b$otherNormalized\\b\\s*[:\\-]');
          final match = otherPattern.firstMatch(upper.substring(valueStart));
          if (match != null) {
            final otherIndex = valueStart + match.start;
            // Ensure it's not just a word in the middle of a sentence
            if (otherIndex >= 0 && otherIndex < valueEnd) {
              valueEnd = otherIndex;
            }
          }
        }
        var value = line
            .substring(valueStart.clamp(0, line.length), valueEnd)
            .replaceFirst(RegExp(r'^\s*[:\-]?\s*'), '')
            .trim();
        if (value.isEmpty && labelIndex > 0) {
          final before = line.substring(0, labelIndex).trim();
          value = RegExp(r'(\S+)\s*$').firstMatch(before)?.group(1) ?? '';
        }
        if (value.isEmpty && index + 1 < lines.length) value = lines[index + 1];
        if (normalizedLabel == 'REPRESENT' ||
            normalizedLabel == 'REPRESENTANTE') {
          value = value.replaceFirst(RegExp(r'^\d+\s+(?=\S)'), '');
        } else if (normalizedLabel == 'FORNECEDOR') {
          value = value;
        }
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static DateTime? _dateHeader(List<String> lines, List<String> labels) {
    final raw = _header(lines, labels);
    final match = RegExp(
      r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})',
    ).firstMatch(raw ?? '');
    if (match == null) return null;
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    return DateTime(
      year,
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }

  static bool _isHeader(String line) {
    final normalized = _normalize(line);
    if (RegExp(r'^\d{1,6}\s+ITENS?\s+TOTAL\b').hasMatch(normalized)) {
      return true;
    }
    return const [
      'REPRESENT',
      'FORNECEDOR',
      'MOSTRUARIO',
      'CONTRATO',
      'DATA ENVIO',
      'DATA TROCA',
      'DATA PAGTO',
      'ZONA VENDA',
      'PRODUTO QTD VAL UN',
      'TOTAL DE ITENS',
      'VALOR TOTAL',
      'CABEÇALHO',
    ].any(normalized.startsWith);
  }

  static (int?, double?) _declaredTotal(List<String> lines) {
    int? qty;
    double? total;

    final singleLinePattern = RegExp(
      r'(?<!\d)(\d{1,6})\s+ITENS?\s+TOTAL\s+(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{2})|\d+(?:[.,]\d{2}))',
      caseSensitive: false,
    );

    final qtyPattern = RegExp(
      r'TOTAL\s+(?:DE\s+)?ITENS\s+(\d{1,6})',
      caseSensitive: false,
    );
    final totalPattern = RegExp(
      r'VALOR\s+TOTAL\s+(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{2})|\d+(?:[.,]\d{2}))',
      caseSensitive: false,
    );

    for (final line in lines.reversed) {
      final singleMatch = singleLinePattern.firstMatch(line);
      if (singleMatch != null) {
        return (
          int.tryParse(singleMatch.group(1)!),
          _brazilianMoney(singleMatch.group(2)!),
        );
      }
      if (qty == null) {
        final qMatch = qtyPattern.firstMatch(line);
        if (qMatch != null) qty = int.tryParse(qMatch.group(1)!);
      }
      if (total == null) {
        final tMatch = totalPattern.firstMatch(line);
        if (tMatch != null) total = _brazilianMoney(tMatch.group(1)!);
      }
      if (qty != null && total != null) break;
    }
    return (qty, total);
  }

  static String _normalize(String value) => value
      .toUpperCase()
      .replaceAll(RegExp('[ÁÀÂÃÄ]'), 'A')
      .replaceAll(RegExp('[ÉÈÊË]'), 'E')
      .replaceAll(RegExp('[ÍÌÎÏ]'), 'I')
      .replaceAll(RegExp('[ÓÒÔÕÖ]'), 'O')
      .replaceAll(RegExp('[ÚÙÛÜ]'), 'U')
      .replaceAll('Ç', 'C');

  static String _title(String value) => value
      .trim()
      .toLowerCase()
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
