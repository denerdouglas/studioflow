import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

import 'clientes_360_page.dart';
import 'configuracao_ia_page.dart';
import 'disponibilidade_page.dart';
import 'agendamento_online_page.dart';
import 'pagamentos_sprint4_page.dart';
import 'simulador_ia_page.dart';

class CentralAtendimentoPage extends StatelessWidget {
  const CentralAtendimentoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final itens =
        <
          ({
            String titulo,
            String subtitulo,
            IconData icone,
            Widget pagina,
            ModuloPermissao permissao,
            AcaoPermissao? acao,
          })
        >[
          (
            titulo: 'Jornadas, folgas e bloqueios',
            subtitulo: 'Disponibilidade real dos profissionais',
            icone: Icons.event_available,
            pagina: const DisponibilidadePage(),
            permissao: ModuloPermissao.agenda,
            acao: AcaoPermissao.gerenciarAgenda,
          ),
          (
            titulo: 'Link público de agendamento',
            subtitulo: 'Configuração e link do agendamento público real',
            icone: Icons.link,
            pagina: const AgendamentoOnlinePage(),
            permissao: ModuloPermissao.agenda,
            acao: AcaoPermissao.gerenciarAgenda,
          ),
          (
            titulo: 'Clientes 360°',
            subtitulo: 'Agenda, compras, pagamentos, faltas e preferências',
            icone: Icons.contact_page_outlined,
            pagina: const Clientes360Page(),
            permissao: ModuloPermissao.clientes,
            acao: null,
          ),
          (
            titulo: 'Configurar assistente',
            subtitulo: 'Nome, linguagem, políticas e perguntas frequentes',
            icone: Icons.tune,
            pagina: const ConfiguracaoIaPage(),
            permissao: ModuloPermissao.configuracoes,
            acao: AcaoPermissao.configurarIa,
          ),
          (
            titulo: 'Simulador de atendimento',
            subtitulo: 'Conversa local usando dados reais do SQLite',
            icone: Icons.forum_outlined,
            pagina: const SimuladorIaPage(),
            permissao: ModuloPermissao.configuracoes,
            acao: AcaoPermissao.visualizarConversas,
          ),
          (
            titulo: 'Pix e pagamentos',
            subtitulo: 'Sinal, cobranças e confirmação manual autorizada',
            icone: Icons.pix,
            pagina: const PagamentosSprint4Page(),
            permissao: ModuloPermissao.financeiro,
            acao: AcaoPermissao.acessarFinanceiro,
          ),
        ];
    final usuario = SessionController.instance.usuario!;
    return Scaffold(
      appBar: AppBar(title: const Text('Atendimento e Agenda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cliente → agenda → assistente → cobrança → confirmação',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'O simulador funciona localmente. WhatsApp, IA online e confirmação automática exigem backend e credenciais.',
                  ),
                ],
              ),
            ),
          ),
          ...itens
              .where(
                (item) =>
                    usuario.pode(item.permissao) &&
                    (item.acao == null || usuario.podeAcao(item.acao!)),
              )
              .map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(item.icone),
                    title: Text(item.titulo),
                    subtitle: Text(item.subtitulo),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => item.pagina),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
