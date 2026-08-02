import 'package:flutter/material.dart';

import '../controllers/subscription_controller.dart';
import '../services/billing/mock_billing_gateway.dart';

class AssinaturasPage extends StatefulWidget {
  const AssinaturasPage({super.key});

  @override
  State<AssinaturasPage> createState() => _AssinaturasPageState();
}

class _AssinaturasPageState extends State<AssinaturasPage> {
  late final SubscriptionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SubscriptionController(MockBillingGateway());
    _controller.addListener(_onStateChange);
    _controller.fetchEntitlement();
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    super.dispose();
  }

  void _onStateChange() {
    if (!mounted) {
      return;
    }

    setState(() {});

    final errorMessage = _controller.state.errorMessage;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      appBar: AppBar(
        title: const Text('StudioFlow Premium'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: state.isLoading && state.status == 'inactive'
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildPlanHeader(state),
                const SizedBox(height: 32),
                _buildStatusSection(state),
                const SizedBox(height: 32),
                _buildActionButtons(state),
              ],
            ),
    );
  }

  Widget _buildPlanHeader(SubscriptionState state) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF70569A),
            Color(0xFF6D4ACB),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D4ACB).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.workspace_premium,
                color: Colors.amber,
                size: 32,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Plano Fundador StudioFlow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'R\$ 14,90',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '/mês',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (state.status == 'inactive') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.5),
                ),
              ),
              child: const Text(
                '20 DIAS GRÁTIS',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Renovação automática. Cancele quando quiser pela loja de aplicativos.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(SubscriptionState state) {
    late final IconData icon;
    late final Color color;
    late final String text;

    switch (state.status) {
      case 'active':
        icon = Icons.check_circle;
        color = const Color(0xFF15996B);
        text = state.isFounder
            ? 'Ativo (Plano Fundador Garantido)'
            : 'Assinatura Ativa';
        break;

      case 'trial':
        icon = Icons.timer;
        color = Colors.amber.shade800;
        text = 'Período de Teste Gratuito';
        break;

      case 'pending':
        icon = Icons.hourglass_empty;
        color = Colors.orange;
        text = 'Pagamento Pendente';
        break;

      case 'grace_period':
        icon = Icons.warning_amber;
        color = Colors.orange;
        text = 'Problema no pagamento (Em carência)';
        break;

      case 'paused':
      case 'on_hold':
        icon = Icons.pause_circle;
        color = Colors.redAccent;
        text = 'Assinatura Pausada/Bloqueada';
        break;

      case 'cancelled':
        icon = Icons.cancel;
        color = Colors.red;
        text = 'Cancelado (Acesso até o fim do período)';
        break;

      case 'expired':
      case 'revoked':
        icon = Icons.block;
        color = Colors.red;
        text = 'Assinatura Expirada';
        break;

      default:
        icon = Icons.info_outline;
        color = const Color(0xFF766A85);
        text = 'Nenhuma assinatura ativa';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color.withAlpha(200),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(SubscriptionState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state.status == 'inactive' ||
        state.status == 'expired' ||
        state.status == 'revoked') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 16,
              ),
              backgroundColor: Colors.grey.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Indisponível na Homologação',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const TextButton(
            onPressed: null,
            child: Text(
              'Restaurar Compras (Desativado)',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Abrindo gerenciador de assinaturas da loja...',
                ),
              ),
            );
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('Gerenciar Assinatura'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              vertical: 16,
            ),
            foregroundColor: const Color(0xFF70569A),
            side: const BorderSide(
              color: Color(0xFF70569A),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}