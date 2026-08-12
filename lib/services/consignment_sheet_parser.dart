import '../models/domain/consignment_document_import.dart';

class ConsignmentSheetParser {
  static final _itemPattern = RegExp(
    r'(?<![A-Z0-9])([A-Z]+\d+|\d{4,14})\s+(\d{1,3})\s+(\d{1,6}(?:[.,]\d{2}))(?!\d)',
    caseSensitive: false,
  );
  static final _reversedItemPattern = RegExp(
    r'(?<![\d.,])(\d{1,3})\s+(\d{1,6}(?:[.,]\d{2}))\s+([A-Z]+\d+|\d{4,14})(?![A-Z0-9])',
    caseSensitive: false,
  );
  static final _categoryPattern = RegExp(
    r'^\s*\d{3}\s*[-–]\s*(.+?)\s*$',
    caseSensitive: false,
  );
  static final _materialPattern = RegExp(
    r'^\s*\*{2,}\s*([^\s]+)',
    caseSensitive: false,
  );

  static ConsignmentDocumentImport parse(String text) {
    final lines = text
        .replaceAll('\u00a0', ' ')
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    String? category;
    String? material;
    final items = <ConsignmentImportItem>[];
    final pending = <String>[];

    for (final line in lines) {
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
      final matches = _itemPattern.allMatches(line).toList();
      final reversedMatches = _reversedItemPattern.allMatches(line).toList();
      final reversed =
          reversedMatches.isNotEmpty &&
          (matches.isEmpty ||
              reversedMatches.first.start < matches.first.start);
      for (final match in reversed ? reversedMatches : matches) {
        items.add(
          ConsignmentImportItem(
            codigo: match.group(reversed ? 3 : 1)!,
            categoria: category ?? '',
            material: material ?? '',
            quantidade: int.parse(match.group(reversed ? 1 : 2)!),
            valorUnitario: _brazilianMoney(match.group(reversed ? 2 : 3)!),
            descricao: category ?? '',
          ),
        );
      }
      if (matches.isEmpty &&
          reversedMatches.isEmpty &&
          RegExp(r'\d{4,}').hasMatch(line) &&
          !_isHeader(line)) {
        pending.add(line);
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

  static double _brazilianMoney(String value) => double.parse(
    value.contains(',')
        ? value.replaceAll('.', '').replaceAll(',', '.')
        : value,
  );

  static String? _representative(List<String> lines) {
    final direct = _header(lines, const ['REPRESENTANTE', 'REPRESENT']);
    if (direct != null &&
        !RegExp(
          r'^(?:VAL|QTD|PRODUTO)\b',
          caseSensitive: false,
        ).hasMatch(direct)) {
      return direct;
    }
    for (final line in lines) {
      if (!_normalize(line).contains('REPRESENT')) continue;
      final cleaned = line
          .replaceAll(RegExp(r'REPRESENT(?:ANTE)?', caseSensitive: false), ' ')
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
          final otherIndex = upper.indexOf(_normalize(other), valueStart);
          if (otherIndex >= 0 && otherIndex < valueEnd) valueEnd = otherIndex;
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
      'MOSTRUARIO',
      'CONTRATO',
      'DATA ENVIO',
      'DATA TROCA',
      'DATA PAGTO',
      'ZONA VENDA',
      'PRODUTO QTD VAL UN',
    ].any(normalized.startsWith);
  }

  static (int?, double?) _declaredTotal(List<String> lines) {
    final pattern = RegExp(
      r'(?<!\d)(\d{1,6})\s+ITENS?\s+TOTAL\s+(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{2})|\d+(?:[.,]\d{2}))',
      caseSensitive: false,
    );
    for (final line in lines.reversed) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        return (
          int.tryParse(match.group(1)!),
          _brazilianMoney(match.group(2)!),
        );
      }
    }
    return (null, null);
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
