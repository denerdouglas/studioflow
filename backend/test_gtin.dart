import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://world.openfoodfacts.org/api/v3/product/7894900011517');
  final response = await http.get(url, headers: {'User-Agent': 'StudioFlow/1.0 (https://studioflowapp.com.br; contato@studioflowapp.com.br)'});
  print('HTTP ${response.statusCode}');
  final json = jsonDecode(response.body);
  print('Result: ${jsonEncode(json['product']?['product_name'])}');
  print('Quantity: ${jsonEncode(json['product']?['quantity'])}');
}

