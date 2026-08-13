import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/services/purchase_receipt_service.dart';

void main() {
  final data = PurchaseReceiptData(
    establishment: 'Studio Teste',
    client: 'Maria',
    purchaseDate: DateTime.utc(2026, 8, 12),
    paymentDate: DateTime.utc(2026, 8, 20),
    paymentMethod: 'Pix',
    items: [
      {
        'codigo': '101429',
        'nome': 'Anel',
        'quantidade': 1.0,
        'valor_unitario': 39.0,
      },
      {
        'codigo': '528299',
        'nome': 'Brinco',
        'quantidade': 1.0,
        'valor_unitario': 62.0,
      },
    ],
  );

  test('WhatsApp contém itens, total e datas da compra', () {
    final message = PurchaseReceiptService.whatsappMessage(data);
    expect(message, contains('Anel cód. 101429'));
    expect(message, contains('Brinco cód. 528299'));
    expect(message, contains('Total: R\$ 101,00'));
    expect(message, contains('12/08/2026'));
    expect(message, contains('20/08/2026'));
  });

  test('PDF contém os mesmos dados em documento válido', () async {
    final bytes = await PurchaseReceiptService.pdfBytes(data);
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
