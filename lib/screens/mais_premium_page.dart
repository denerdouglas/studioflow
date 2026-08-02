import 'package:flutter/material.dart';

import '../core/routes/app_routes.dart';
import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import 'academy_page.dart';
import '../controllers/academy_controller.dart';
import '../repositories/academy_repository.dart';
import 'aniversarios_page.dart';
import 'assinaturas_page.dart';
import 'central_atendimento_page.dart';
import 'commercial_center_page.dart';
import 'ia_local_page.dart';
import 'loja_salao_page.dart';
import 'cardapio_page.dart';
import 'privacy_page.dart';
import 'producao_page.dart';

class MaisPremiumPage extends StatelessWidget {
  final StudioFlowTheme tema;

  const MaisPremiumPage({super.key, required this.tema});

  @override
  Widget build(BuildContext context) {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) {
      return Scaffold(
        body: Center(child: Text('Sessão expirada')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Menu StudioFlow', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 110),
        children: [
          _buildUserProfile(usuario, context),
          const SizedBox(height: 24),
          _buildSectionTitle('Gestão & Vendas'),
          if (usuario.pode(ModuloPermissao.agenda))
            _buildMenuItem(
              context: context,
              icon: Icons.support_agent,
              color: const Color(0xFF6D4ACB),
              title: 'Atendimento e Agenda',
              subtitle: 'Disponibilidade, clientes 360º, Pix',
              destination: const CentralAtendimentoPage(),
            ),
          if (usuario.pode(ModuloPermissao.lojaSalao))
            _buildMenuItem(
              context: context,
              icon: Icons.store_mall_directory_outlined,
              color: const Color(0xFF15996B),
              title: 'Loja do salão',
              subtitle: 'Produtos, vendas, estoque',
              destination: const LojaSalaoPage(),
            ),
          if (usuario.pode(ModuloPermissao.lojaSalao))
            _buildMenuItem(
              context: context,
              icon: Icons.restaurant_menu,
              color: const Color(0xFFD64D64),
              title: 'Cardápio do Salão',
              subtitle: 'Cortesias e serviços complementares',
              destination: const MenuPage(),
            ),
          if (usuario.pode(ModuloPermissao.clientes))
            _buildMenuItem(
              context: context,
              icon: Icons.cake_outlined,
              color: const Color(0xFFB04A7A),
              title: 'Aniversários',
              subtitle: 'Ações de relacionamento',
              destination: const AniversariosPage(),
            ),
            
          const SizedBox(height: 24),
          _buildSectionTitle('StudioFlow Hub'),
          _buildMenuItem(
            context: context,
            icon: Icons.school_outlined,
            color: const Color(0xFF15996B),
            title: 'StudioFlow Acadêmico',
            subtitle: 'Capacitação e gestão',
            destination: AcademyPage(
              controller: AcademyController(
                academyRepository: AcademyRepository(),
              ),
            ),
          ),
          if (usuario.pode(ModuloPermissao.configuracoes))
            _buildMenuItem(
              context: context,
              icon: Icons.workspace_premium_outlined,
              color: Colors.amber.shade700,
              title: 'Assinaturas e Planos',
              subtitle: 'Gerencie seu plano atual',
              destination: const AssinaturasPage(),
            ),
          if (usuario.pode(ModuloPermissao.configuracoes))
            _buildMenuItem(
              context: context,
              icon: Icons.business_center_outlined,
              color: const Color(0xFF70569A),
              title: 'StudioFlow Comercial',
              subtitle: 'Configuração avançada de catálogo',
              destination: const CommercialCenterPage(),
            ),
          _buildMenuItem(
            context: context,
            icon: Icons.auto_awesome,
            color: const Color(0xFF6D4ACB),
            title: 'StudioFlow IA',
            subtitle: 'Insights com inteligência local',
            destination: const IaLocalPage(),
          ),
          if (usuario.pode(ModuloPermissao.configuracoes))
            _buildMenuItem(
              context: context,
              icon: Icons.rocket_launch_outlined,
              color: const Color(0xFF3078C5),
              title: 'Produção e Status',
              subtitle: 'Status offline e dependências',
              destination: const ProducaoPage(),
            ),

          const SizedBox(height: 24),
          _buildSectionTitle('Conta e Segurança'),
          _buildMenuItem(
            context: context,
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF766A85),
            title: 'Privacidade e LGPD',
            subtitle: 'Controle de dados',
            destination: const PrivacyPage(),
          ),
          const SizedBox(height: 16),
          _buildLogoutButton(context),
        ],
      ),
    );
  }

  Widget _buildUserProfile(UsuarioAcesso usuario, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: tema.corPrincipal.withValues(alpha: 0.1),
            child: Text(
              usuario.nome.isNotEmpty ? usuario.nome[0].toUpperCase() : 'U',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: tema.corPrincipal,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usuario.nome,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2140),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${usuario.funcao.nome} • ${usuario.codigoComercio}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF766A85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: Color(0xFF70569A),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2D2140)),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: Color(0xFF766A85)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFFDCD5E4)),
        onTap: () => Navigator.push(
          context,
          AppRoutes.material(builder: (_) => destination),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sair da conta?'),
            content: const Text(
              'Será necessário informar comércio, login e senha novamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64D64)),
                child: const Text('Sair'),
              ),
            ],
          ),
        );
        if (confirmar == true) {
          await SessionController.instance.sair();
        }
      },
      icon: const Icon(Icons.logout, color: Color(0xFFD64D64)),
      label: const Text('Sair da conta', style: TextStyle(color: Color(0xFFD64D64))),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFD64D64)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
