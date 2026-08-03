import 'package:flutter/material.dart';

class AssinaturasPage extends StatefulWidget {
  const AssinaturasPage({super.key});

  @override
  State<AssinaturasPage> createState() => _AssinaturasPageState();
}

class _AssinaturasPageState extends State<AssinaturasPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      appBar: AppBar(
        title: const Text('StudioFlow Premium'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.settings_outlined, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Configuração pendente',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Cobranças recorrentes e assinaturas ainda dependem da configuração da loja e da validação segura no backend. Nenhuma compra pode ser realizada nesta versão.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
