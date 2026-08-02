import 'package:flutter/material.dart';

class MarketplaceStubPage extends StatelessWidget {
  const MarketplaceStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      appBar: AppBar(
        title: const Text('Marketplace StudioFlow'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF70569A).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront,
                  size: 64,
                  color: Color(0xFF70569A),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Em breve!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2140),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Estamos preparando as melhores ofertas de produtos, ferramentas e parceiros exclusivos para impulsionar o seu negócio.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF766A85),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.search),
                label: const Text('Pesquisa Indisponível'),
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
