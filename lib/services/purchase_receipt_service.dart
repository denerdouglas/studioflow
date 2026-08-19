import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/helpers/app_formatters.dart';

class PurchaseReceiptData {
  final String establishment;
  final String client;
  final DateTime purchaseDate;
  final DateTime? paymentDate;
  final String paymentMethod;
  final String? notes;
  final List<Map<String, Object?>> items;
  final String? commandNumber;
  final String? clientPhone;
  final double discount;
  final double? amountPaid;
  final String? status;
  final DateTime? dueDate;

  const PurchaseReceiptData({
    required this.establishment,
    required this.client,
    required this.purchaseDate,
    this.paymentDate,
    required this.paymentMethod,
    this.notes,
    required this.items,
    this.commandNumber,
    this.clientPhone,
    this.discount = 0,
    this.amountPaid,
    this.status,
    this.dueDate,
  });

  double get total => items.fold(
    0,
    (sum, item) =>
        sum +
        (item['quantidade'] as num).toDouble() *
            (item['valor_unitario'] as num).toDouble(),
  );

  double get pending => (total - discount - (amountPaid ?? total))
      .clamp(0, double.infinity)
      .toDouble();
}

class PurchaseReceiptService {
  static String whatsappMessage(PurchaseReceiptData data) {
    final lines = data.items
        .map((item) {
          final quantity = (item['quantidade'] as num).toDouble();
          final unit = (item['valor_unitario'] as num).toDouble();
          return '• ${_quantity(quantity)}x ${item['nome']} cód. ${item['codigo']} '
              '— ${AppFormatters.moeda(unit * quantity)}';
        })
        .join('\n');
    return 'StudioFlow / ${data.establishment}\n'
        '${data.commandNumber == null ? '' : 'Comanda #${data.commandNumber}\n'}'
        'Cliente: ${data.client}\n\nItens:\n$lines\n\n'
        'Subtotal: ${AppFormatters.moeda(data.total)}\n'
        '${data.discount <= 0 ? '' : 'Desconto: ${AppFormatters.moeda(data.discount)}\n'}'
        'Total: ${AppFormatters.moeda(data.total - data.discount)}\n'
        'Pago: ${AppFormatters.moeda(data.amountPaid ?? data.total - data.discount)}\n'
        'Pendente: ${AppFormatters.moeda(data.pending)}\n'
        '${data.status == null ? '' : 'Status: ${data.status}\n'}'
        '${data.paymentMethod.trim().isEmpty ? '' : 'Forma de pagamento: ${data.paymentMethod}\n'}'
        '${data.dueDate == null ? '' : 'Vencimento: ${AppFormatters.data(data.dueDate!)}\n'}'
        'Data da compra: ${AppFormatters.data(data.purchaseDate)}'
        '${data.paymentDate == null ? '' : '\nData de pagamento: ${AppFormatters.data(data.paymentDate!)}'}'
        '\n\nObrigado pela preferência!';
  }

  static Future<Uint8List> pdfBytes(PurchaseReceiptData data) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'StudioFlow / ${data.establishment}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Cliente: ${data.client}'),
          pw.Text('Data da compra: ${AppFormatters.data(data.purchaseDate)}'),
          pw.Text('Forma de pagamento: ${data.paymentMethod}'),
          if (data.paymentDate != null)
            pw.Text(
              'Pagamento/vencimento: ${AppFormatters.data(data.paymentDate!)}',
            ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Código',
              'Descrição/categoria',
              'Qtd.',
              'Unitário',
            ],
            data: data.items
                .map(
                  (item) => [
                    '${item['codigo'] ?? ''}',
                    '${item['nome'] ?? ''}',
                    _quantity((item['quantidade'] as num).toDouble()),
                    AppFormatters.moeda(
                      (item['valor_unitario'] as num).toDouble(),
                    ),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Total: ${AppFormatters.moeda(data.total)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (data.notes?.trim().isNotEmpty ?? false)
            pw.Text('Observação: ${data.notes!.trim()}'),
        ],
      ),
    );
    return document.save();
  }

  static String _quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceAll('.', ',');
}
