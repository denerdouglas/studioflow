import 'package:flutter/material.dart';

import '../core/routes/app_routes.dart';
import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';
import 'agenda_page.dart';
import 'aniversarios_page.dart';
import 'caixa_page.dart';
import 'cardapio_page.dart';
import 'central_atendimento_page.dart';
import 'commercial_center_page.dart';
import 'clientes_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'funcionarios_page.dart';
import 'ia_local_page.dart';
import 'loja_salao_page.dart';
import 'producao_page.dart';
import 'privacy_page.dart';
import 'relatorios_page.dart';
import 'servicos_page.dart';
import 'usuarios_page.dart';

class MaisSprint2Page extends StatelessWidget {
  final StudioFlowTheme tema;

  const MaisSprint2Page({super.key, required this.tema});

  UsuarioAcesso get _usuario => SessionController.instance.usuario!;

  @override
  Widget build(BuildContext context) {
    final itens = <_ItemMenu>[
      _ItemMenu(
        'Agenda',
        Icons.calendar_month,
        ModuloPermissao.agenda,
        const AgendaPage(),
        acao: AcaoPermissao.gerenciarAgenda,
      ),
      _ItemMenu(
        'Clientes',
        Icons.people_outline,
        ModuloPermissao.clientes,
        const ClientesPage(),
      ),
      _ItemMenu(
        'Serviços',
        Icons.design_services,
        ModuloPermissao.servicos,
        const ServicosPage(),
      ),
      _ItemMenu(
        'Equipe profissional',
        Icons.groups_outlined,
        ModuloPermissao.funcionarios,
        const FuncionariosPage(),
      ),
      _ItemMenu(
        'Funcionários e acessos',
        Icons.badge_outlined,
        ModuloPermissao.administracaoUsuarios,
        const UsuariosPage(),
      ),
      _ItemMenu(
        'Caixa',
        Icons.account_balance_wallet,
        ModuloPermissao.caixa,
        const CaixaPage(),
      ),
      _ItemMenu(
        'Financeiro',
        Icons.payments_outlined,
        ModuloPermissao.financeiro,
        const FinanceiroPage(),
        acao: AcaoPermissao.acessarFinanceiro,
      ),
      _ItemMenu(
        'Relatórios',
        Icons.bar_chart,
        ModuloPermissao.relatorios,
        const RelatoriosPage(),
        acao: AcaoPermissao.acessarRelatorios,
      ),
      _ItemMenu(
        'Estoque',
        Icons.inventory_2_outlined,
        ModuloPermissao.estoque,
        const EstoquePage(),
        acao: AcaoPermissao.visualizarEstoque,
      ),
      _ItemMenu(
        'Configurações',
        Icons.settings_outlined,
        ModuloPermissao.configuracoes,
        const ConfiguracoesPage(),
      ),
    ];
    return Scaffold(
      backgroundColor: tema.fundo,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Mais recursos'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Card(
            color: tema.corPrincipal,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                _usuario.nome,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${_usuario.funcao.nome} • ${_usuario.codigoComercio}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...itens
              .where(
                (item) =>
                    _usuario.pode(item.permissao) &&
                    (item.acao == null || _usuario.podeAcao(item.acao!)),
              )
              .map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(item.icone, color: tema.corPrincipal),
                    title: Text(item.titulo),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      AppRoutes.material(builder: (_) => item.pagina),
                    ),
                  ),
                ),
              ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome, color: Color(0xFF6D4ACB)),
              title: const Text('StudioFlow IA local'),
              subtitle: const Text('Insights com dados deste aparelho'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const IaLocalPage()),
              ),
            ),
          ),
          if (_usuario.pode(ModuloPermissao.clientes))
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.cake_outlined,
                  color: Color(0xFFB04A7A),
                ),
                title: const Text('Aniversários'),
                subtitle: const Text(
                  'Clientes do dia e ações de relacionamento',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppRoutes.material(builder: (_) => const AniversariosPage()),
                ),
              ),
            ),
          if (_usuario.pode(ModuloPermissao.agenda))
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.support_agent,
                  color: Color(0xFF6D4ACB),
                ),
                title: const Text('Atendimento e Agenda'),
                subtitle: const Text(
                  'Disponibilidade, clientes 360°, IA e Pix',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppRoutes.material(
                    builder: (_) => const CentralAtendimentoPage(),
                  ),
                ),
              ),
            ),
          if (_usuario.pode(ModuloPermissao.lojaSalao))
            Card(
              child: ListTile(
                leading: const Icon(Icons.store_mall_directory_outlined),
                title: const Text('Loja do salão'),
                subtitle: const Text('Produtos, vendas, estoque e reposição'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppRoutes.material(builder: (_) => const LojaSalaoPage()),
                ),
              ),
            ),
          if (_usuario.pode(ModuloPermissao.lojaSalao))
            Card(
              child: ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: const Text('Cardápio do Salão'),
                subtitle: const Text('Cortesias, itens pagos e complementos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppRoutes.material(builder: (_) => const MenuPage()),
                ),
              ),
            ),
          if (_usuario.pode(ModuloPermissao.configuracoes))
            Card(
              child: ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('StudioFlow Comercial 1.0'),
                subtitle: const Text(
                  'Assinatura, configuração, catálogo e recursos futuros',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppRoutes.material(
                    builder: (_) => const CommercialCenterPage(),
                  ),
                ),
              ),
            ),
          if (_usuario.pode(ModuloPermissao.configuracoes))
            Card(
              child: ListTile(
                leading: const Icon(Icons.rocket_launch_outlined),
                title: const Text('Produção e sincronização'),
                subtitle: const Text('Status offline e dependências externas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  AppRoutes.material(builder: (_) => const ProducaoPage()),
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacidade e LGPD'),
              subtitle: const Text('Exportação e solicitação de exclusão'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                AppRoutes.material(builder: (_) => const PrivacyPage()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
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
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              );
              if (confirmar == true) {
                await SessionController.instance.sair();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sair da conta'),
          ),
        ],
      ),
    );
  }
}

class _ItemMenu {
  final String titulo;
  final IconData icone;
  final ModuloPermissao permissao;
  final Widget pagina;
  final AcaoPermissao? acao;

  const _ItemMenu(
    this.titulo,
    this.icone,
    this.permissao,
    this.pagina, {
    this.acao,
  });
}
